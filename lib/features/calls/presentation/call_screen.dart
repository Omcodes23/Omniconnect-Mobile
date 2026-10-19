import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/auth_provider.dart';
import '../../../services/call_media_service.dart';
import '../../../services/signalr_service.dart';

enum CallState { ringing, connecting, connected, ended }

class CallData {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final bool isVideoCall;
  final String? callId;

  CallData({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.isVideoCall = false,
    this.callId,
  });
}

class CallScreen extends ConsumerStatefulWidget {
  final CallData callData;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.callData,
    this.isIncoming = false,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  CallState _callState = CallState.ringing;
  bool _isMuted = false;
  bool _isSpeakerOff = false;
  bool _isVideoEnabled = false;
  String _endedMessage = 'The call has been disconnected';

  Timer? _callTimer;
  Timer? _fallbackTimer;
  int _secondsElapsed = 0;
  String? _callId;

  CallMediaService? _media;
  StreamSubscription<Uint8List>? _localVideoSub;
  StreamSubscription<Uint8List>? _remoteVideoSub;
  Uint8List? _localFrame;
  Uint8List? _remoteFrame;

  late final SignalRService _signalR;
  late final void Function(Map<String, dynamic> call) _acceptedHandler;
  late final void Function(Map<String, dynamic> call) _rejectedHandler;
  late final void Function(Map<String, dynamic> call) _endedHandler;
  late final void Function(String senderId, String kind, String payload)
      _mediaHandler;

  @override
  void initState() {
    super.initState();
    _callId = widget.callData.callId;
    _isVideoEnabled = widget.callData.isVideoCall;

    _signalR = ref.read(signalRServiceProvider);
    _acceptedHandler = _handleCallAccepted;
    _rejectedHandler = _handleCallRejected;
    _endedHandler = _handleCallEnded;
    _mediaHandler = _handleMedia;
    _signalR.onCallAccepted = _acceptedHandler;
    _signalR.onCallRejected = _rejectedHandler;
    _signalR.onCallEnded = _endedHandler;
    _signalR.onCallMediaReceived = _mediaHandler;

    if (!widget.isIncoming) {
      _startCall();
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _fallbackTimer?.cancel();
    _localVideoSub?.cancel();
    _remoteVideoSub?.cancel();
    if (identical(_signalR.onCallAccepted, _acceptedHandler)) {
      _signalR.onCallAccepted = null;
    }
    if (identical(_signalR.onCallRejected, _rejectedHandler)) {
      _signalR.onCallRejected = null;
    }
    if (identical(_signalR.onCallEnded, _endedHandler)) {
      _signalR.onCallEnded = null;
    }
    if (identical(_signalR.onCallMediaReceived, _mediaHandler)) {
      _signalR.onCallMediaReceived = null;
    }
    unawaited(_media?.dispose());
    _media = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Signaling
  // ---------------------------------------------------------------------------

  Future<void> _startCall() async {
    final api = ref.read(apiServiceProvider);
    try {
      final call = await api.initiateCall(
        widget.callData.userId,
        widget.callData.isVideoCall ? 'Video' : 'Audio',
      );
      final id = call['id']?.toString();
      if (id != null && id.isNotEmpty) {
        _callId = id;
      }
    } catch (e) {
      debugPrint('initiateCall failed: $e');
    }

    if (!mounted) return;

    if (_callId == null || _callId!.isEmpty) {
      _finish('Unable to start the call');
      return;
    }

    // The callee's acceptance normally arrives over SignalR; fall back to a
    // connected state if that event is missed so the call is still usable.
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _callState != CallState.ringing) return;
      _handleCallAccepted(<String, dynamic>{'id': _callId});
    });
  }

  void _handleCallAccepted(Map<String, dynamic> call) {
    if (!mounted || _callState == CallState.ended) return;
    if (!_matchesCall(call)) return;
    _fallbackTimer?.cancel();
    if (_callState != CallState.connected) {
      setState(() {
        _callState = CallState.connected;
      });
      _startTimer();
    }
    unawaited(_startMedia());
  }

  void _handleCallRejected(Map<String, dynamic> call) {
    if (!mounted || _callState == CallState.ended) return;
    if (!_matchesCall(call)) return;
    _finish('Call declined');
  }

  void _handleCallEnded(Map<String, dynamic> call) {
    if (!mounted || _callState == CallState.ended) return;
    if (!_matchesCall(call)) return;
    _finish('The call has been disconnected');
  }

  void _handleMedia(String senderId, String kind, String payload) {
    _media?.handleMedia(senderId, kind, payload);
  }

  bool _matchesCall(Map<String, dynamic> call) {
    final incomingId = call['id']?.toString();
    if (incomingId == null || incomingId.isEmpty) return true;
    final currentId = _callId;
    if (currentId == null || currentId.isEmpty) return true;
    return incomingId == currentId;
  }

  Future<void> _acceptCall() async {
    final api = ref.read(apiServiceProvider);
    if (_callId != null && _callId!.isNotEmpty) {
      try {
        await api.answerCall(_callId!);
      } catch (e) {
        debugPrint('answerCall failed: $e');
      }
    }
    if (!mounted) return;

    setState(() {
      _callState = CallState.connecting;
    });
    unawaited(_startMedia());

    // The backend broadcasts CallAccepted to both parties; keep a fallback in
    // case that event does not reach this device.
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _callState != CallState.connecting) return;
      _handleCallAccepted(<String, dynamic>{'id': _callId});
    });
  }

  Future<void> _rejectCall() async {
    _fallbackTimer?.cancel();
    final api = ref.read(apiServiceProvider);
    if (_callId != null && _callId!.isNotEmpty) {
      try {
        await api.rejectCall(_callId!);
      } catch (e) {
        debugPrint('rejectCall failed: $e');
      }
    }
    _finish('Call declined');
  }

  Future<void> _endCall() async {
    final api = ref.read(apiServiceProvider);
    if (_callId != null && _callId!.isNotEmpty) {
      try {
        await api.endCall(_callId!);
      } catch (e) {
        debugPrint('endCall failed: $e');
      }
    }
    _finish('The call has been disconnected');
  }

  void _finish(String message) {
    if (!mounted) return;
    _callTimer?.cancel();
    _fallbackTimer?.cancel();
    unawaited(_stopMedia());
    setState(() {
      _callState = CallState.ended;
      _endedMessage = message;
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) Navigator.pop(context);
    });
  }

  // ---------------------------------------------------------------------------
  // Media
  // ---------------------------------------------------------------------------

  Future<void> _startMedia() async {
    if (_media != null || _callState == CallState.ended) return;
    final service = CallMediaService(
      signalR: _signalR,
      peerUserId: widget.callData.userId,
    );
    _media = service;

    _localVideoSub = service.localVideoFrames.listen((frame) {
      if (!mounted) return;
      setState(() {
        _localFrame = frame;
      });
    });
    _remoteVideoSub = service.remoteVideoFrames.listen((frame) {
      if (!mounted) return;
      setState(() {
        _remoteFrame = frame;
      });
    });

    await service.start(video: widget.callData.isVideoCall && _isVideoEnabled);
  }

  Future<void> _stopMedia() async {
    await _localVideoSub?.cancel();
    await _remoteVideoSub?.cancel();
    _localVideoSub = null;
    _remoteVideoSub = null;
    final service = _media;
    _media = null;
    await service?.dispose();
  }

  void _startTimer() {
    _callTimer?.cancel();
    _secondsElapsed = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _media?.setMicMuted(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOff = !_isSpeakerOff;
    });
    _media?.setSpeakerEnabled(!_isSpeakerOff);
  }

  Future<void> _toggleVideo() async {
    final next = !_isVideoEnabled;
    setState(() {
      _isVideoEnabled = next;
      if (!next) {
        _localFrame = null;
      }
    });
    await _media?.setVideoEnabled(next);
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _statusText {
    switch (_callState) {
      case CallState.ringing:
        if (widget.isIncoming) {
          return 'Incoming ${widget.callData.isVideoCall ? 'Video' : 'Voice'} Call...';
        }
        return 'Calling...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return _formatTime(_secondsElapsed);
      case CallState.ended:
        return '';
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo = widget.callData.isVideoCall &&
        _callState == CallState.connected &&
        _remoteFrame != null;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0c0e1a),
              AppTheme.surface.withValues(alpha: 0.9),
              const Color(0xFF0c0e1a),
            ],
          ),
        ),
        child: SafeArea(
          child: _callState == CallState.ended
              ? _buildEndedView()
              : Stack(
                  children: [
                    if (showRemoteVideo)
                      Positioned.fill(
                        child: Image.memory(
                          _remoteFrame!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    if (showRemoteVideo)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.45),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                              ],
                              stops: const [0, 0.45, 1],
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: Column(
                        children: [
                          _buildCallHeader(showRemoteVideo),
                          const Spacer(),
                          _buildControls(),
                        ],
                      ),
                    ),
                    if (widget.callData.isVideoCall &&
                        _callState != CallState.ringing)
                      Positioned(
                        top: 84,
                        right: 16,
                        child: _buildLocalPreview(),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEndedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.call_end_rounded, size: 64, color: AppTheme.error),
          const SizedBox(height: 16),
          const Text(
            'Call Ended',
            style: TextStyle(
              fontSize: 22,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _endedMessage,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHeader(bool overVideo) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          if (!overVideo)
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryIndigo.withValues(alpha: 0.35),
                    blurRadius: 50,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 64,
                backgroundColor: AppTheme.surfaceElevated,
                child: Text(
                  widget.callData.userName.isNotEmpty
                      ? widget.callData.userName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 52,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            widget.callData.userName,
            style: const TextStyle(
              fontSize: 28,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _statusText,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textMuted,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalPreview() {
    final frame = _localFrame;
    return Container(
      width: 104,
      height: 148,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 12, spreadRadius: 1),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: frame != null
          ? Image.memory(frame, fit: BoxFit.cover, gaplessPlayback: true)
          : const Center(
              child: Icon(
                Icons.videocam_off_rounded,
                color: AppTheme.textMuted,
                size: 28,
              ),
            ),
    );
  }

  Widget _buildControls() {
    final bool ringingIncoming =
        _callState == CallState.ringing && widget.isIncoming;
    final bool ringingOutgoing = _callState == CallState.ringing;

    if (ringingIncoming) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallControlButton(
              icon: Icons.call_end_rounded,
              label: 'Decline',
              color: Colors.white,
              backgroundColor: AppTheme.error,
              onPressed: _rejectCall,
              isDestructive: true,
            ),
            const SizedBox(width: 80),
            _CallControlButton(
              icon: widget.callData.isVideoCall
                  ? Icons.videocam_rounded
                  : Icons.phone_rounded,
              label: 'Accept',
              color: Colors.white,
              backgroundColor: AppTheme.success,
              onPressed: _acceptCall,
            ),
          ],
        ),
      );
    }

    if (ringingOutgoing || _callState == CallState.connecting) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: _CallControlButton(
          icon: Icons.call_end_rounded,
          label: 'Cancel',
          color: Colors.white,
          backgroundColor: AppTheme.error,
          onPressed: _endCall,
          isDestructive: true,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallControlButton(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _isMuted ? 'Unmute' : 'Mute',
            color: _isMuted ? Colors.white : Colors.white70,
            backgroundColor:
                _isMuted ? AppTheme.primaryIndigo : Colors.white12,
            onPressed: _toggleMute,
          ),
          if (widget.callData.isVideoCall)
            _CallControlButton(
              icon: _isVideoEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              label: _isVideoEnabled ? 'Video On' : 'Video Off',
              color: _isVideoEnabled ? Colors.white70 : Colors.white,
              backgroundColor: _isVideoEnabled
                  ? Colors.white12
                  : AppTheme.primaryIndigo,
              onPressed: _toggleVideo,
            ),
          _CallControlButton(
            icon: _isSpeakerOff
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            label: _isSpeakerOff ? 'Muted' : 'Speaker',
            color: _isSpeakerOff ? Colors.white : Colors.white70,
            backgroundColor:
                _isSpeakerOff ? AppTheme.primaryIndigo : Colors.white12,
            onPressed: _toggleSpeaker,
          ),
          _CallControlButton(
            icon: Icons.call_end_rounded,
            label: 'End',
            color: Colors.white,
            backgroundColor: AppTheme.error,
            onPressed: _endCall,
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            boxShadow: isDestructive
                ? [
                    BoxShadow(
                      color: AppTheme.error.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            icon: Icon(icon, color: color, size: 26),
            onPressed: onPressed,
            padding: const EdgeInsets.all(18),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
