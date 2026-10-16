import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'auth_provider.dart';
import 'lan_discovery_service.dart';

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
  final Map<String, DeviceInfoDto> _mergedDevices = {};

  @override
  DeviceListState build() {
    ref.onDispose(() {
      _lanSub?.cancel();
    });

    // Listen to local LAN UDP discovery events
    final lanService = ref.watch(lanDiscoveryServiceProvider);
    _lanSub?.cancel();
    _lanSub = lanService.onDevicesChanged.listen((lanDevices) {
      _mergeLanDevices(lanDevices);
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

  /// Register this device with the backend and start UDP LAN broadcast.
  Future<void> registerThisDevice({
    required String deviceId,
    required String deviceName,
    String deviceModel = 'Android',
    String? ipAddress,
    int port = 5000,
  }) async {
    _selfDeviceId = deviceId;
    final auth = ref.read(authStateProvider);

    // 1. Start Local UDP LAN Discovery & Broadcast
    final lanService = ref.read(lanDiscoveryServiceProvider);
    await lanService.startDiscovery(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceModel: deviceModel,
      userId: auth.user?.id,
      userName: auth.user?.displayName,
    );

    // 2. Register with Central Backend API
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/devices/register', {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceModel': deviceModel,
        'roles': 'Client',
        'availableTransports': ['LAN', 'WiFiDirect', 'Bluetooth', 'Internet'],
        'ipAddress': ipAddress,
        'port': port,
        'userId': auth.user?.id,
        'userName': auth.user?.displayName,
      });
    } catch (_) {
      // Registration is best-effort
    }
  }
}

final deviceListProvider =
    NotifierProvider<DeviceListNotifier, DeviceListState>(DeviceListNotifier.new);
