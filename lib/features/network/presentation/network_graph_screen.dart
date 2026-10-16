import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/auth_provider.dart';

class NetworkGraphState {
  final List<NetworkDevice> devices;
  final bool isLoading;

  const NetworkGraphState({
    this.devices = const [],
    this.isLoading = false,
  });
}

class NetworkDevice {
  final String id;
  final String name;
  final String model;
  final String transport;
  final bool isOnline;
  final double x;
  final double y;

  NetworkDevice({
    required this.id,
    required this.name,
    this.model = '',
    this.transport = 'LAN',
    this.isOnline = true,
    this.x = 0,
    this.y = 0,
  });
}

final networkGraphProvider = FutureProvider.autoDispose<List<NetworkDevice>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final result = await api.getDevices();

  // The backend node is infrastructure, not a peer — keep it off the graph.
  final data = result.devices
      .where((e) =>
          e is Map<String, dynamic> &&
          e['deviceId']?.toString() != result.selfDeviceId)
      .toList();

  return data.asMap().entries.map((entry) {
    final i = entry.key;
    final d = entry.value as Map<String, dynamic>;
    final angle = (i * 2 * pi) / max(data.length, 1) - pi / 2;
    final radius = 120.0;
    return NetworkDevice(
      id: d['deviceId']?.toString() ?? '$i',
      name: d['deviceName'] ?? 'Unknown',
      model: d['deviceModel'] ?? '',
      transport: (d['availableTransports'] as List?)?.where((t) => t == 'LAN' || t == 'Bluetooth').first ?? 'LAN',
      isOnline: true,
      x: 200 + radius * cos(angle),
      y: 200 + radius * sin(angle),
    );
  }).toList();
});

class NetworkGraphScreen extends ConsumerStatefulWidget {
  const NetworkGraphScreen({super.key});

  @override
  ConsumerState<NetworkGraphScreen> createState() => _NetworkGraphScreenState();
}

class _NetworkGraphScreenState extends ConsumerState<NetworkGraphScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      ref.invalidate(networkGraphProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Color _transportColor(String transport) {
    switch (transport) {
      case 'Bluetooth':
        return const Color(0xFF06b6d4);
      case 'Wi-Fi':
      case 'WiFiDirect':
        return const Color(0xFF6366f1);
      case 'LAN':
      default:
        return const Color(0xFF10b981);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(networkGraphProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Network Graph'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: () => ref.invalidate(networkGraphProvider),
          ),
        ],
      ),
      body: devicesAsync.when(
        data: (devices) {
          if (devices.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_find, size: 64, color: AppTheme.textMuted),
                  SizedBox(height: 16),
                  Text(
                    'No devices discovered',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Devices on your network will appear here',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(networkGraphProvider);
              await ref.read(networkGraphProvider.future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: 500,
                child: Stack(
                  children: [
                    // Center node (current device)
                    Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: AppTheme.linearGradient(),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'You',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Connection lines
                    ...devices.map((device) {
                      return Positioned(
                        left: 200 + device.x - 1,
                        top: 200 + device.y - 1,
                        child: CustomPaint(
                          size: const Size(2, 200),
                          painter: _ConnectionLinePainter(
                            color: _transportColor(device.transport),
                          ),
                        ),
                      );
                    }),

                    // Device nodes
                    ...devices.asMap().entries.map((entry) {
                      final i = entry.key;
                      final device = entry.value;
                      final angle = (i * 2 * pi) / max(devices.length, 1) - pi / 2;
                      final radius = 120.0;
                      final x = 200 + radius * cos(angle);
                      final y = 200 + radius * sin(angle);

                      return Positioned(
                        left: x - 30,
                        top: y - 30,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _transportColor(device.transport),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _transportColor(device.transport).withValues(alpha: 0.2),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  device.name.isNotEmpty ? device.name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              device.name,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _transportColor(device.transport).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                device.transport,
                                style: TextStyle(
                                  color: _transportColor(device.transport),
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // Device list at bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Discovered Devices',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...devices.map((d) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: d.isOnline ? AppTheme.success : AppTheme.textMuted,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      d.name,
                                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    d.transport,
                                    style: TextStyle(
                                      color: _transportColor(d.transport),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              Text('Failed to load devices',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
              const SizedBox(height: 8),
              Text('$e', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionLinePainter extends CustomPainter {
  final Color color;
  _ConnectionLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
