import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'auth_provider.dart';
import 'lan_discovery_service.dart';
import 'bluetooth_service.dart';

class DeviceInfoDto {
  final String deviceId;
  final String deviceName;
  final String deviceModel;
  final String platform;
  final String? ipAddress;
  final int port;
  final bool isOnline;
  final String? userId;
  final String? userName;
  final List<String> availableTransports;

  DeviceInfoDto({
    required this.deviceId,
    required this.deviceName,
    this.deviceModel = '',
    this.platform = 'Unknown',
    this.ipAddress,
    this.port = 0,
    this.isOnline = true,
    this.userId,
    this.userName,
    this.availableTransports = const ['LAN', 'Internet'],
  });

  factory DeviceInfoDto.fromJson(Map<String, dynamic> json) {
    List<String> transports = ['LAN', 'Internet'];
    if (json['availableTransports'] is List) {
      transports = (json['availableTransports'] as List)
          .map((e) => e.toString())
          .toList();
    }
    return DeviceInfoDto(
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName'] ?? 'Unknown Device',
      deviceModel: json['deviceModel'] ?? '',
      platform: json['platform'] ?? (json['deviceModel']?.toString().contains('Android') == true ? 'Android' : 'Desktop'),
      ipAddress: json['ipAddress']?.toString(),
      port: json['port'] is int ? json['port'] as int : 0,
      isOnline: json['isOnline'] ?? true,
      userId: json['userId']?.toString(),
      userName: json['userName']?.toString(),
      availableTransports: transports,
    );
  }

  bool get isChattable => userId != null && userId!.isNotEmpty;
}

class DeviceListState {
  final List<DeviceInfoDto> devices;
  final bool isLoading;
  final String? error;

  const DeviceListState({
    this.devices = const [],
    this.isLoading = false,
    this.error,
  });

  DeviceListState copyWith({
    List<DeviceInfoDto>? devices,
    bool? isLoading,
    String? error,
  }) {
    return DeviceListState(
      devices: devices ?? this.devices,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class DeviceListNotifier extends Notifier<DeviceListState> {
  String? _selfDeviceId;
  String _serverDeviceId = '';
  StreamSubscription<List<DeviceInfoDto>>? _lanSub;
  StreamSubscription<BluetoothDevice>? _btSub;
  StreamSubscription<bool>? _btAvailSub;
  final Map<String, DeviceInfoDto> _mergedDevices = {};
  BluetoothService? _bluetoothService;

  @override
  DeviceListState build() {
    ref.onDispose(() {
      _lanSub?.cancel();
      _btSub?.cancel();
      _btAvailSub?.cancel();
      _bluetoothService?.dispose();
    });

    // Listen to local LAN UDP discovery events
    final lanService = ref.watch(lanDiscoveryServiceProvider);
    _lanSub?.cancel();
    _lanSub = lanService.onDevicesChanged.listen((lanDevices) {
      _mergeLanDevices(lanDevices);
    });

    // Listen to Bluetooth discovery events
    _bluetoothService = ref.watch(bluetoothServiceProvider);
    _bluetoothService!.probe().then((available) {
      if (available) {
        _btSub?.cancel();
        _btSub = _bluetoothService!.onDeviceDiscovered.listen((btDevice) {
          _mergeBluetoothDevice(btDevice);
        });
      }
    });

    return const DeviceListState();
  }

  void _mergeLanDevices(List<DeviceInfoDto> lanDevices) {
    for (final d in lanDevices) {
      if (d.deviceId == _selfDeviceId) continue;
      if (_serverDeviceId.isNotEmpty && d.deviceId == _serverDeviceId) continue;
      _mergedDevices[d.deviceId] = d;
    }
    state = state.copyWith(devices: _mergedDevices.values.toList());
  }

  void _mergeBluetoothDevice(BluetoothDevice btDevice) {
    if (btDevice.id == _selfDeviceId) return;
    if (_serverDeviceId.isNotEmpty && btDevice.id == _serverDeviceId) return;
    final dto = DeviceInfoDto(
      deviceId: btDevice.id,
      deviceName: btDevice.name,
      deviceModel: btDevice.type,
      platform: 'Android',
      isOnline: true,
      availableTransports: ['Bluetooth'],
    );
    _mergedDevices[btDevice.id] = dto;
    state = state.copyWith(devices: _mergedDevices.values.toList());
  }

  /// Load discovered devices from the backend (merging with LAN discovery).
  Future<void> loadDevices() async {
    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.getDevices();

      // Hide this phone and the backend node the user is signed in to.
      if (result.selfDeviceId.isNotEmpty) _serverDeviceId = result.selfDeviceId;

      final apiDevices = result.devices
          .map((e) => DeviceInfoDto.fromJson(e as Map<String, dynamic>))
          .where((d) => d.deviceId != _selfDeviceId && d.deviceId != _serverDeviceId)
          .toList();

      for (final d in apiDevices) {
        _mergedDevices[d.deviceId] = d;
      }

      state = state.copyWith(
        devices: _mergedDevices.values.toList(),
        isLoading: false,
      );
    } catch (e) {
      if (_mergedDevices.isEmpty) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  /// Gets or generates a persistent device ID for this mobile device.
  static Future<String> getPersistentDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('persistent_device_id');
    if (id == null || id.isEmpty) {
      id = 'mobile-${const Uuid().v4().substring(0, 8)}';
      await prefs.setString('persistent_device_id', id);
    }
    return id;
  }

  /// Detect the local LAN IP address of this device.
  static Future<String?> _detectLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          // Prefer non-link-local addresses
          if (!addr.address.startsWith('169.254.')) {
            return addr.address;
          }
        }
      }
      // Fallback: any non-loopback IPv4
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Register this device with the backend and start UDP LAN broadcast.
  Future<void> registerThisDevice({
    required String deviceId,
    required String deviceName,
    String deviceModel = 'Android',
    String? ipAddress,
    int port = 5001, // Changed default to 5001 (direct listener port)
  }) async {
    _selfDeviceId = deviceId;
    final auth = ref.read(authStateProvider);

    // Auto-detect LAN IP if not provided
    final detectedIp = ipAddress ?? await _detectLocalIpAddress();

    // 1. Start Local UDP LAN Discovery & Broadcast
    final lanService = ref.read(lanDiscoveryServiceProvider);
    await lanService.startDiscovery(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceModel: deviceModel,
      userId: auth.user?.id,
      userName: auth.user?.displayName,
      ipAddress: detectedIp, // Pass explicit IP to LAN service
    );

    // 2. Start Bluetooth Discovery (if available)
    final btService = ref.read(bluetoothServiceProvider);
    final btAvailable = await btService.probe();
    if (btAvailable) {
      await btService.enable();
      await btService.startServer();
    }

    // 3. Register with Central Backend API
    try {
      final api = ref.read(apiServiceProvider);
      final transports = ['LAN', 'WiFiDirect', 'Internet'];
      if (btAvailable) transports.add('Bluetooth');
      await api.post('/api/devices/register', {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceModel': deviceModel,
        'roles': 'Client',
        'availableTransports': transports,
        'ipAddress': detectedIp,
        'port': port,
        'userId': auth.user?.id,
        'userName': auth.user?.displayName,
      });
    } catch (_) {
      // Registration is best-effort
    }
  }
}

// Bluetooth service provider
final bluetoothServiceProvider = Provider<BluetoothService>((ref) {
  final service = BluetoothService();
  ref.onDispose(() => service.dispose());
  return service;
});

final deviceListProvider =
    NotifierProvider<DeviceListNotifier, DeviceListState>(DeviceListNotifier.new);