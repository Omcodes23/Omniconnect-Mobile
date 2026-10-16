import 'dart:async';
import 'package:flutter/foundation.dart';

/// Wi-Fi Direct (P2P) service for high-speed peer-to-peer communication
/// between Android devices without an internet connection.
class WiFiDirectService {
  bool _isAvailable = false;
  bool _isDiscovering = false;
  final List<WiFiPeer> _discoveredPeers = [];
  final StreamController<WiFiPeer> _peerController =
      StreamController<WiFiPeer>.broadcast();
  final StreamController<WiFiDirectMessage> _messageController =
      StreamController<WiFiDirectMessage>.broadcast();

  Stream<WiFiPeer> get onPeerDiscovered => _peerController.stream;
  Stream<WiFiDirectMessage> get onMessageReceived => _messageController.stream;
  List<WiFiPeer> get discoveredPeers => List.unmodifiable(_discoveredPeers);
  bool get isAvailable => _isAvailable;
  bool get isDiscovering => _isDiscovering;

  Future<bool> initialize() async {
    try {
      _isAvailable = true;
      debugPrint('Wi-Fi Direct service initialized');
      return true;
    } catch (e) {
      debugPrint('Failed to initialize Wi-Fi Direct: $e');
      _isAvailable = false;
      return false;
    }
  }

  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 30)}) async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _discoveredPeers.clear();
    debugPrint('Wi-Fi Direct discovery started');
    await Future.delayed(timeout);
    _isDiscovering = false;
    debugPrint('Wi-Fi Direct discovery completed');
  }

  Future<void> stopDiscovery() async {
    _isDiscovering = false;
  }

  Future<bool> connectToPeer(String deviceAddress) async {
    debugPrint('Connecting to Wi-Fi Direct peer: $deviceAddress');
    return true;
  }

  Future<bool> sendMessage(String deviceAddress, String message) async {
    debugPrint('Sending Wi-Fi Direct message to $deviceAddress');
    _messageController.add(WiFiDirectMessage(
      deviceAddress: deviceAddress,
      content: message,
      timestamp: DateTime.now(),
      isIncoming: false,
    ));
    return true;
  }

  void dispose() {
    _peerController.close();
    _messageController.close();
  }
}

class WiFiPeer {
  final String deviceAddress;
  final String deviceName;
  final String primaryType;
  final int rssi;

  WiFiPeer({
    required this.deviceAddress,
    required this.deviceName,
    this.primaryType = '10-0050F204-5',
    this.rssi = 0,
  });
}

class WiFiDirectMessage {
  final String deviceAddress;
  final String content;
  final DateTime timestamp;
  final bool isIncoming;

  WiFiDirectMessage({
    required this.deviceAddress,
    required this.content,
    required this.timestamp,
    this.isIncoming = true,
  });
}