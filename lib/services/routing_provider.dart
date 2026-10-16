import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

/// Transport types matching the C# TransportType enum.
class TransportType {
  static const internet = 'Internet';
  static const lan = 'LAN';
  static const bluetooth = 'Bluetooth';
  static const wifiDirect = 'WiFi Direct';

  /// Map C# enum int → readable name (0=Internet,1=LAN,2=Bluetooth,3=WiFiDirect).
  static String fromInt(dynamic v) {
    if (v is String) return v;
    final n = v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    switch (n) {
      case 1:
        return lan;
      case 2:
        return bluetooth;
      case 3:
        return wifiDirect;
      default:
        return internet;
    }
  }
}

class RouteInfoDto {
  final String deviceId;
  final String deviceName;
  final String activeTransport;
  final double compositeScore;
  final double latencyMs;
  final double bandwidthMbps;
  final bool isAvailable;
  final DateTime? lastSeen;

  RouteInfoDto({
    required this.deviceId,
    required this.deviceName,
    required this.activeTransport,
    required this.compositeScore,
    required this.latencyMs,
    required this.bandwidthMbps,
    required this.isAvailable,
    this.lastSeen,
  });

  factory RouteInfoDto.fromJson(Map<String, dynamic> json) => RouteInfoDto(
        deviceId: json['deviceId']?.toString() ?? '',
        deviceName: json['deviceName'] ?? 'Unknown',
        activeTransport: TransportType.fromInt(json['activeTransport']),
        compositeScore: (json['compositeScore'] is num)
            ? (json['compositeScore'] as num).toDouble()
            : 0,
        latencyMs: (json['latencyMs'] is num)
            ? (json['latencyMs'] as num).toDouble()
            : 0,
        bandwidthMbps: (json['bandwidthMbps'] is num)
            ? (json['bandwidthMbps'] as num).toDouble()
            : 0,
        isAvailable: json['isAvailable'] ?? false,
        lastSeen: json['lastSeen'] != null
            ? DateTime.tryParse(json['lastSeen'])
            : null,
      );

  /// One-line summary like: "via LAN · 12ms · 100 Mbps"
  String get transportSummary =>
      '$activeTransport · ${latencyMs.toStringAsFixed(0)}ms';
}

class RoutingState {
  final List<RouteInfoDto> routes;
  final bool isLoading;
  final String? error;

  const RoutingState({
    this.routes = const [],
    this.isLoading = false,
    this.error,
  });

  RoutingState copyWith({
    List<RouteInfoDto>? routes,
    bool? isLoading,
    String? error,
  }) {
    return RoutingState(
      routes: routes ?? this.routes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  RouteInfoDto? routeFor(String deviceId) {
    for (final r in routes) {
      if (r.deviceId == deviceId) return r;
    }
    return null;
  }
}

class RoutingNotifier extends Notifier<RoutingState> {
  @override
  RoutingState build() => const RoutingState();

  /// Load routing table (best transport per discovered device).
  Future<void> loadRoutes() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/routing/routes');
      final routes = data
          .map((e) => RouteInfoDto.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(routes: routes, isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final routingProvider =
    NotifierProvider<RoutingNotifier, RoutingState>(RoutingNotifier.new);
