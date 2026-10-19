import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:image/image.dart' as img;
import 'package:record/record.dart' hide IosAudioCategory;

import 'signalr_service.dart';

/// Bidirectional call media carried over the existing SignalR hub.
///
/// Audio: 16 kHz mono PCM16, sliced into 40 ms frames (1280 bytes) and sent as
/// base64. Video: JPEG frames ~480 px wide at a deliberately low frame rate.
/// Both directions share the same relay (`SendCallMedia` -> `CallMediaReceived`)
/// so no WebRTC/TURN/codec dependencies are required.
class CallMediaService {
  CallMediaService({required this.signalR, required this.peerUserId});

  final SignalRService signalR;
  final String peerUserId;

  static const int sampleRate = 16000;
  static const int frameBytes = 1280; // 40 ms of PCM16 mono @ 16 kHz
  static const int maxQueuedAudioFrames = 4;
  static const int maxQueuedVideoFrames = 2;
  static const int videoTargetWidth = 480;
  static const int videoFps = 7;
  static const int jpegQuality = 55;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSubscription;

  final List<int> _pending = <int>[];
  int _audioInFlight = 0;
  int _videoInFlight = 0;

  bool _started = false;
  bool _disposed = false;

  bool _micMuted = false;
  bool _speakerEnabled = true;
  bool _videoEnabled = false;

  CameraController? _camera;
  bool _cameraStarting = false;
  bool _frameBusy = false;
  int _lastFrameMs = 0;

  final StreamController<Uint8List> _localVideo =
      StreamController<Uint8List>.broadcast();
  final StreamController<Uint8List> _remoteVideo =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get localVideoFrames => _localVideo.stream;
  Stream<Uint8List> get remoteVideoFrames => _remoteVideo.stream;

  bool get isVideoEnabled => _videoEnabled;

  Future<void> start({required bool video}) async {
    if (_started || _disposed) return;
    _started = true;
    _videoEnabled = video;
    await _startAudio();
    if (video) {
      await _startCamera();
    }
  }

  // ---------------------------------------------------------------------------
  // Audio
  // ---------------------------------------------------------------------------

  Future<void> _startAudio() async {
    try {
      await FlutterPcmSound.setup(
        sampleRate: sampleRate,
        channelCount: 1,
        iosAudioCategory: IosAudioCategory.playAndRecord,
      );
      await FlutterPcmSound.setFeedThreshold(
        maxQueuedAudioFrames * (frameBytes ~/ 2),
      );
    } catch (e) {
      debugPrint('PCM playback setup failed: $e');
    }

    if (_disposed) {
      try {
        await FlutterPcmSound.release();
      } catch (_) {}
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('Microphone permission not granted');
        return;
      }
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
          androidConfig: AndroidRecordConfig(
            useLegacy: false,
            muteAudio: false,
            manageBluetooth: false,
            audioSource: AndroidAudioSource.voiceCommunication,
            speakerphone: true,
            audioManagerMode: AudioManagerMode.modeInCommunication,
          ),
        ),
      );
      _micSubscription = stream.listen(
        _onMicData,
        onError: (Object e) => debugPrint('Microphone stream error: $e'),
      );
      if (_disposed) {
        await _micSubscription?.cancel();
        _micSubscription = null;
        try {
          await _recorder.stop();
        } catch (_) {}
        try {
          await _recorder.dispose();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Microphone start failed: $e');
    }
  }

  void _onMicData(Uint8List chunk) {
    if (_disposed || _micMuted || chunk.isEmpty) return;
    _pending.addAll(chunk);

    while (_pending.length >= frameBytes) {
      if (_audioInFlight >= maxQueuedAudioFrames) {
        // Keep latency bounded: discard the oldest backlog instead of
        // queueing audio that would be played out several seconds late.
        _pending.removeRange(0, frameBytes);
        continue;
      }
      final frame = Uint8List.fromList(_pending.sublist(0, frameBytes));
      _pending.removeRange(0, frameBytes);
      _audioInFlight++;
      final payload = base64Encode(frame);
      signalR
          .sendCallMedia(peerUserId, 'audio', payload)
          .whenComplete(() => _audioInFlight--);
    }

    // Guard against pathological chunk sizes from the recorder.
    final cap = frameBytes * maxQueuedAudioFrames;
    if (_pending.length > cap) {
      _pending.removeRange(0, _pending.length - cap);
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming media
  // ---------------------------------------------------------------------------

  void handleMedia(String senderId, String kind, String payload) {
    if (_disposed || senderId != peerUserId) return;

    if (kind == 'audio') {
      if (!_speakerEnabled) return;
      try {
        final bytes = base64Decode(payload);
        if (bytes.isEmpty) return;
        FlutterPcmSound.feed(
          PcmArrayInt16(
            bytes: ByteData.sublistView(bytes),
          ),
        );
      } catch (e) {
        debugPrint('Audio playback failed: $e');
      }
      return;
    }

    if (kind == 'video') {
      if (!_videoEnabled) return;
      try {
        final bytes = base64Decode(payload);
        if (bytes.isEmpty) return;
        _remoteVideo.add(bytes);
      } catch (e) {
        debugPrint('Video decode failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Camera / outgoing video
  // ---------------------------------------------------------------------------

  Future<void> _startCamera() async {
    if (_disposed || !_videoEnabled || _camera != null || _cameraStarting) {
      return;
    }
    _cameraStarting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('No camera available');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (_disposed || !_videoEnabled) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      await controller.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('Camera start failed: $e');
    } finally {
      _cameraStarting = false;
    }
  }

  Future<void> _stopCamera() async {
    final controller = _camera;
    _camera = null;
    if (controller == null) return;
    try {
      await controller.stopImageStream();
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
  }

  void _onCameraFrame(CameraImage frame) {
    if (_disposed || !_videoEnabled || _frameBusy) return;
    if (frame.format.group != ImageFormatGroup.yuv420 ||
        frame.planes.length < 3) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastFrameMs < (1000 ~/ videoFps)) return;
    _lastFrameMs = nowMs;

    _frameBusy = true;
    try {
      final jpeg = _encodeJpeg(frame);
      if (jpeg == null) return;
      _localVideo.add(jpeg);
      if (_videoInFlight < maxQueuedVideoFrames) {
        _videoInFlight++;
        signalR
            .sendCallMedia(peerUserId, 'video', base64Encode(jpeg))
            .whenComplete(() => _videoInFlight--);
      }
    } catch (e) {
      debugPrint('Video encode failed: $e');
    } finally {
      _frameBusy = false;
    }
  }

  Uint8List? _encodeJpeg(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    if (width <= 0 || height <= 0) return null;

    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final yStride = yPlane.bytesPerRow;
    final uStride = uPlane.bytesPerRow;
    final vStride = vPlane.bytesPerRow;
    final uStep = uPlane.bytesPerPixel ?? 1;
    final vStep = vPlane.bytesPerPixel ?? 1;

    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      final yRow = y * yStride;
      final uRow = (y >> 1) * uStride;
      final vRow = (y >> 1) * vStride;
      for (var x = 0; x < width; x++) {
        final yValue = yBytes[yRow + x];
        final uIndex = uRow + (x >> 1) * uStep;
        final vIndex = vRow + (x >> 1) * vStep;
        if (uIndex >= uBytes.length || vIndex >= vBytes.length) continue;
        final uValue = uBytes[uIndex] - 128;
        final vValue = vBytes[vIndex] - 128;
        final r = (yValue + 1.402 * vValue).clamp(0, 255).toInt();
        final g = (yValue - 0.344136 * uValue - 0.714136 * vValue)
            .clamp(0, 255)
            .toInt();
        final b = (yValue + 1.772 * uValue).clamp(0, 255).toInt();
        image.setPixelRgb(x, y, r, g, b);
      }
    }

    final scaled = width > videoTargetWidth
        ? img.copyResize(
            image,
            width: videoTargetWidth,
            interpolation: img.Interpolation.average,
          )
        : image;
    return Uint8List.fromList(img.encodeJpg(scaled, quality: jpegQuality));
  }

  Future<void> setVideoEnabled(bool enabled) async {
    if (_disposed) return;
    _videoEnabled = enabled;
    if (enabled) {
      await _startCamera();
    } else {
      await _stopCamera();
    }
  }

  void setMicMuted(bool muted) {
    _micMuted = muted;
    if (muted) {
      _pending.clear();
    }
  }

  void setSpeakerEnabled(bool enabled) {
    _speakerEnabled = enabled;
  }

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    _pending.clear();

    try {
      await _micSubscription?.cancel();
    } catch (_) {}
    _micSubscription = null;

    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _recorder.dispose();
    } catch (_) {}

    await _stopCamera();

    try {
      await FlutterPcmSound.release();
    } catch (_) {}

    try {
      await _localVideo.close();
    } catch (_) {}
    try {
      await _remoteVideo.close();
    } catch (_) {}
  }
}
