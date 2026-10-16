import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'device_provider.dart';

/// Service that discovers and broadcasts devices over the local network
/// using UDP Multicast (239.255.100.50) and Subnet Broadcast (255.255.255.255).
class LanDiscoveryService {
  static final InternetAddress multicastGroup = InternetAddress('239.255.100.50');
  static const int discoveryPort = 45678;

  RawDatagramSocket? _receiverSocket;
  RawDatagramSocket? _senderSocket;
  Timer? _broadcastTimer;
  Timer? _purgeTimer;

  final Map<String, DeviceInfoDto> _discoveredMap = {};
  final Map<String, DateTime> _deviceExpirations = {};

  final StreamController<List<DeviceInfoDto>> _devicesController =
      StreamController<List<DeviceInfoDto>>.broadcast();

  Stream<List<DeviceInfoDto>> get onDevicesChanged => _devicesController.stream;
  List<DeviceInfoDto> get devices => _discoveredMap.values.toList();

  String _selfDeviceId = '';
  String _selfDeviceName = 'Mobile';
  String _selfDeviceModel = 'Android';
  String? _selfUserId;
  String? _selfUserName;

  /// Starts listening for UDP discovery broadcasts and initiates periodic presence broadcasts.
  Future<void> startDiscovery({
    required String deviceId,
    required String deviceName,
    String deviceModel = 'Mobile',
    String? userId,
    String? userName,
  }) async {
    _selfDeviceId = deviceId;
    _selfDeviceName = deviceName;
    _selfDeviceModel = deviceModel;
    _selfUserId = userId;
    _selfUserName = userName;

    await stopDiscovery();

    try {
      // 1. Initialize receiver socket bound to discovery port
      _receiverSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );

      try {
        _receiverSocket?.joinMulticast(multicastGroup);
      } catch (e) {
        debugPrint('[LAN Discovery] Multicast join note: $e');
      }

      _receiverSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _receiverSocket?.receive();
          if (datagram != null) {
            _handleIncomingPacket(datagram.data, datagram.address);
          }
        }
      });

      // 2. Initialize broadcaster socket
      _senderSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _senderSocket?.broadcastEnabled = true;

      // Broadcast immediately
      _broadcastPresence();

      // Schedule periodic broadcast every 4 seconds
      _broadcastTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _broadcastPresence();
      });

      // Schedule purge for stale devices every 5 seconds
      _purgeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _purgeStaleDevices();
      });

      debugPrint('[LAN Discovery] Started listening on port $discoveryPort');
    } catch (e) {
      debugPrint('[LAN Discovery] Failed to start socket listener: $e');
    }
  }

  void updateUserInfo({String? userId, String? userName}) {
    _selfUserId = userId;
    _selfUserName = userName;
    _broadcastPresence();
  }

  void _broadcastPresence() {
    if (_senderSocket == null || _selfDeviceId.isEmpty) return;

    try {
      final payload = {
        'deviceId': _selfDeviceId,
        'deviceName': _selfDeviceName,
        'deviceModel': _selfDeviceModel,
        'roles': 'Client',
        'availableTransports': ['LAN', 'WiFiDirect', 'Internet'],
        'port': 5001,
        'userId': _selfUserId,
        'userName': _selfUserName,
      };

      final bytes = utf8.encode(jsonEncode(payload));

      // 1. Send to Multicast Group
      try {
        _senderSocket?.send(bytes, multicastGroup, discoveryPort);
      } catch (_) {}

      // 2. Send to Subnet Broadcast Address
      try {
        _senderSocket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
      } catch (_) {}
    } catch (e) {
      debugPrint('[LAN Discovery] Broadcast error: $e');
    }
  }

  void _handleIncomingPacket(Uint8List data, InternetAddress remoteAddress) {
    try {
      final jsonStr = utf8.decode(data);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final deviceId = json['deviceId']?.toString() ?? '';
      if (deviceId.isEmpty || deviceId == _selfDeviceId) return;

      final deviceName = json['deviceName']?.toString() ?? 'Device';
      final deviceModel = json['deviceModel']?.toString() ?? '';
      final userId = json['userId']?.toString();
      final userName = json['userName']?.toString();
      final ipAddress = json['ipAddress']?.toString() ?? remoteAddress.address;
      final port = json['port'] is int ? json['port'] as int : 5000;

      final dto = DeviceInfoDto(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceModel: deviceModel,
        platform: deviceModel.contains('Android')
            ? 'Android'
            : (deviceModel.contains('iOS') ? 'iOS' : 'Desktop'),
        ipAddress: ipAddress,
        port: port,
        isOnline: true,
        userId: userId,
        userName: userName,
      );

      _discoveredMap[deviceId] = dto;
      _deviceExpirations[deviceId] = DateTime.now().add(const Duration(seconds: 15));
      _devicesController.add(_discoveredMap.values.toList());
    } catch (e) {
      debugPrint('[LAN Discovery] Packet parse error: $e');
    }
  }

  void _purgeStaleDevices() {
    final now = DateTime.now();
    final expiredIds = _deviceExpirations.entries
        .where((e) => e.value.isBefore(now))
        .map((e) => e.key)
        .toList();

    if (expiredIds.isNotEmpty) {
      for (final id in expiredIds) {
        _discoveredMap.remove(id);
        _deviceExpirations.remove(id);
      }
      _devicesController.add(_discoveredMap.values.toList());
    }
  }

  Future<void> stopDiscovery() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _purgeTimer?.cancel();
    _purgeTimer = null;

    try {
      _receiverSocket?.close();
      _receiverSocket = null;
    } catch (_) {}

    try {
      _senderSocket?.close();
      _senderSocket = null;
    } catch (_) {}
  }

  void dispose() {
    stopDiscovery();
    _devicesController.close();
  }
}

final lanDiscoveryServiceProvider = Provider<LanDiscoveryService>((ref) {
  final service = LanDiscoveryService();
  ref.onDispose(() => service.dispose());
  return service;
});
