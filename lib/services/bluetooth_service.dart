import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'bluetooth_frame.dart';

/// Real standalone Bluetooth transport for Android (RFCOMM via platform channel).
///
/// Talks to `BluetoothChannelHandler` on the Android side. Availability is
/// probed honestly: if the channel/adapter isn't present, isAvailable is false
/// and the Bluetooth label is not advertised — satisfying the "only show the
/// label if it actually works" rule.
///
/// All messages are ephemeral: kept in memory only, never written to the DB.
class BluetoothService {
  static const MethodChannel _channel = MethodChannel('omniconnect/bluetooth');

  bool _isAvailable = false;
  bool _isScanning = false;
  bool _serverStarted = false;
  final List<BluetoothDevice> _discoveredDevices = [];
  final StreamController<BluetoothDevice> _deviceController =
      StreamController<BluetoothDevice>.broadcast();
  final StreamController<BluetoothMessage> _messageController =
      StreamController<BluetoothMessage>.broadcast();

  Stream<BluetoothDevice> get onDeviceDiscovered => _deviceController.stream;
  Stream<BluetoothMessage> get onMessageReceived => _messageController.stream;
  List<BluetoothDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  bool get isAvailable => _isAvailable;
  bool get isScanning => _isScanning;
  bool get isServerStarted => _serverStarted;

  BluetoothService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<void> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onConnected':
        _serverStarted = true;
        break;
      case 'onMessageReceived':
        final payloadStr = call.arguments as String?;
        if (payloadStr != null) {
          try {
            final decoded = jsonDecode(payloadStr) as Map<String, dynamic>;
            final payload = BluetoothChatPayload(
              type: decoded['type']?.toString() ?? 'chat',
              fromPeerId: decoded['fromPeerId']?.toString() ?? '',
              fromPeerName: decoded['fromPeerName']?.toString() ?? 'Peer',
              toPeerId: decoded['toPeerId']?.toString() ?? '',
              content: decoded['content']?.toString() ?? '',
              clientMessageId: decoded['clientMessageId']?.toString() ?? '',
              sentAt: decoded['sentAt']?.toString() ?? '',
            );
            _messageController.add(BluetoothMessage(
              deviceId: payload.fromPeerId,
              content: payload.content,
              timestamp: DateTime.tryParse(payload.sentAt) ?? DateTime.now(),
              isIncoming: true,
              fromPeerName: payload.fromPeerName,
              clientMessageId: payload.clientMessageId,
            ));
          } catch (_) {}
        }
        break;
    }
  }

  /// Probe the platform for real Bluetooth RFCOMM capability.
  Future<bool> probe() async {
    try {
      final available = await _channel.invokeMethod('isAvailable') as bool?;
      _isAvailable = available == true;
      return _isAvailable;
    } catch (_) {
      _isAvailable = false;
      return false;
    }
  }

  /// Ensure Bluetooth is enabled on the device.
  Future<bool> enable() async {
    if (!_isAvailable) return false;
    try {
      final enabled = await _channel.invokeMethod('enable') as bool?;
      _isAvailable = enabled == true;
      return _isAvailable == true;
    } catch (_) {
      return false;
    }
  }

  /// Start the RFCOMM server so peers can connect to this device.
  Future<bool> startServer() async {
    if (!_isAvailable) return false;
    try {
      final ok = await _channel.invokeMethod('startServer') as bool?;
      _serverStarted = ok == true;
      return _serverStarted;
    } catch (_) {
      return false;
    }
  }

  /// Connect to a paired peer by its Bluetooth MAC address.
  Future<bool> connectTo(String deviceAddress) async {
    if (!_isAvailable) return false;
    try {
      final ok = await _channel.invokeMethod('connectTo', {'deviceAddress': deviceAddress}) as bool?;
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Send a framed chat message over Bluetooth to a connected peer.
  ///
  /// Returns false when no peer is connected — never pretends success.
  Future<bool> sendMessage({
    required String toPeerId,
    required String fromPeerId,
    required String fromPeerName,
    required String content,
  }) async {
    if (!_isAvailable || !_serverStarted) return false;
    try {
      // Build OM Bluetooth Frame payload (matches Desktop Shared Models)
      final framePayload = BluetoothFrame.chatPayload(
        fromPeerId: fromPeerId,
        fromPeerName: fromPeerName,
        toPeerId: toPeerId,
        content: content,
        clientMessageId: DateTime.now().millisecondsSinceEpoch.toString(),
        sentAt: DateTime.now().toUtc(),
      );
      final frame = BluetoothFrame(frameType: BluetoothFrame.frameTypeChat, payload: framePayload);
      final frameBytes = frame.toBytes();
      
      // Send raw frame bytes; Android side expects full OM frame
      final ok = await _channel.invokeMethod('sendMessage', {
        'frameBytes': frameBytes,
      }) as bool?;
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopServer() async {
    _serverStarted = false;
    try {
      await _channel.invokeMethod('stopServer');
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _serverStarted = false;
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {}
  }

  void dispose() {
    stopServer();
    _deviceController.close();
    _messageController.close();
  }
}

class BluetoothDevice {
  final String id;
  final String name;
  final String type;
  final int rssi;

  BluetoothDevice({
    required this.id,
    required this.name,
    this.type = 'Unknown',
    this.rssi = 0,
  });
}

class BluetoothMessage {
  final String deviceId;
  final String content;
  final DateTime timestamp;
  final bool isIncoming;
  final String? fromPeerName;
  final String? clientMessageId;

  BluetoothMessage({
    required this.deviceId,
    required this.content,
    required this.timestamp,
    this.isIncoming = true,
    this.fromPeerName,
    this.clientMessageId,
  });
}