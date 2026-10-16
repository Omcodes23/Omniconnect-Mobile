import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/auth_provider.dart';

class AdminState {
  final double uptimeHours;
  final int memoryUsageMB;
  final int activeConnections;
  final int totalUsers;
  final List<AdminUser> users;
  final bool isLoading;
  final String? error;

  const AdminState({
    this.uptimeHours = 0,
    this.memoryUsageMB = 0,
    this.activeConnections = 0,
    this.totalUsers = 0,
    this.users = const [],
    this.isLoading = false,
    this.error,
  });

  AdminState copyWith({
    double? uptimeHours,
    int? memoryUsageMB,
    int? activeConnections,
    int? totalUsers,
    List<AdminUser>? users,
    bool? isLoading,
    String? error,
  }) {
    return AdminState(
      uptimeHours: uptimeHours ?? this.uptimeHours,
      memoryUsageMB: memoryUsageMB ?? this.memoryUsageMB,
      activeConnections: activeConnections ?? this.activeConnections,
      totalUsers: totalUsers ?? this.totalUsers,
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AdminUser {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String role;
  final String status;
  final DateTime createdAt;

  AdminUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    this.role = 'user',
    this.status = 'Offline',
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id']?.toString() ?? '',
        username: json['username'] ?? '',
        displayName: json['displayName'] ?? json['username'] ?? '',
        email: json['email'] ?? '',
        role: json['role'] ?? 'user',
        status: json['status'] ?? 'Offline',
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class AdminNotifier extends Notifier<AdminState> {
  @override
  AdminState build() => const AdminState();

  Future<void> loadMetrics() async {
    state = state.copyWith(isLoading: true);
    try {
      final api = ref.read(apiServiceProvider);
      final metrics = await api.post('/api/admin/metrics', null);
      state = state.copyWith(
        uptimeHours: (metrics['uptimeHours'] as num?)?.toDouble() ?? 0,
        memoryUsageMB: metrics['memoryUsageMB'] as int? ?? 0,
        activeConnections: metrics['activeConnections'] as int? ?? 0,
        totalUsers: metrics['totalUsers'] as int? ?? 0,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load metrics: $e');
    }
  }

  Future<void> loadUsers() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/admin/users');
      final users =
          data.map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList();
      state = state.copyWith(users: users);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load users: $e');
    }
  }
}

final adminProvider = NotifierProvider<AdminNotifier, AdminState>(AdminNotifier.new);

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(adminProvider.notifier);
      notifier.loadMetrics();
      notifier.loadUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Admin Panel',
            style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: AppTheme.primaryIndigo),
              onPressed: () {
                final notifier = ref.read(adminProvider.notifier);
                notifier.loadMetrics();
                notifier.loadUsers();
              },
            ),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryIndigo,
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                final notifier = ref.read(adminProvider.notifier);
                await notifier.loadMetrics();
                await notifier.loadUsers();
              },
              color: AppTheme.primaryIndigo,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // System Health Section
                  const Text(
                    'System Health',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MetricCard(
                        icon: Icons.timer_outlined,
                        label: 'Uptime',
                        value: '${state.uptimeHours.toStringAsFixed(1)}h',
                        color: AppTheme.success,
                      ),
                      const SizedBox(width: 12),
                      _MetricCard(
                        icon: Icons.memory_outlined,
                        label: 'Memory',
                        value: '${state.memoryUsageMB} MB',
                        color: AppTheme.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MetricCard(
                        icon: Icons.wifi_outlined,
                        label: 'Connections',
                        value: '${state.activeConnections}',
                        color: AppTheme.primaryPurple,
                      ),
                      const SizedBox(width: 12),
                      _MetricCard(
                        icon: Icons.people_outlined,
                        label: 'Total Users',
                        value: '${state.totalUsers}',
                        color: AppTheme.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // User Management Section
                  const Text(
                    'User Management',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (state.users.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No users found',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else
                    ...state.users.map((user) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: user.role == 'admin'
                                  ? AppTheme.warning.withValues(alpha: 0.15)
                                  : AppTheme.primaryIndigo
                                      .withValues(alpha: 0.12),
                              child: Text(
                                user.displayName[0].toUpperCase(),
                                style: TextStyle(
                                  color: user.role == 'admin'
                                      ? AppTheme.warning
                                      : AppTheme.primaryIndigo,
                                ),
                              ),
                            ),
                            title: Text(
                              user.displayName,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary),
                            ),
                            subtitle: Text(
                              '${user.email} - ${user.role}',
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: user.status == 'Online'
                                    ? AppTheme.success.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                user.status,
                                style: TextStyle(
                                  color: user.status == 'Online'
                                      ? AppTheme.success
                                      : Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
