import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/auth_provider.dart';

class DeviceInfoData {
  final String deviceName;
  final String deviceModel;
  final String platform;
  final String? ipAddress;

  DeviceInfoData({
    required this.deviceName,
    required this.deviceModel,
    required this.platform,
    this.ipAddress,
  });

  factory DeviceInfoData.fromJson(Map<String, dynamic> json) => DeviceInfoData(
        deviceName: json['deviceName'] ?? 'Unknown',
        deviceModel: json['deviceModel'] ?? 'Unknown',
        platform: json['platform'] ?? 'Unknown',
        ipAddress: json['ipAddress'] as String?,
      );
}

class SettingsState {
  final String serverUrl;
  final bool isDarkMode;
  final bool notificationsEnabled;
  final bool soundEnabled;
  final DeviceInfoData? deviceInfo;
  final bool isLoadingDeviceInfo;

  const SettingsState({
    this.serverUrl = 'http://10.0.2.2:5000',
    this.isDarkMode = true,
    this.notificationsEnabled = true,
    this.soundEnabled = true,
    this.deviceInfo,
    this.isLoadingDeviceInfo = false,
  });

  SettingsState copyWith({
    String? serverUrl,
    bool? isDarkMode,
    bool? notificationsEnabled,
    bool? soundEnabled,
    DeviceInfoData? deviceInfo,
    bool? isLoadingDeviceInfo,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      isLoadingDeviceInfo: isLoadingDeviceInfo ?? this.isLoadingDeviceInfo,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void setServerUrl(String url) {
    state = state.copyWith(serverUrl: url);
  }

  void toggleDarkMode(bool value) {
    state = state.copyWith(isDarkMode: value);
  }

  void toggleNotifications(bool value) {
    state = state.copyWith(notificationsEnabled: value);
  }

  void toggleSound(bool value) {
    state = state.copyWith(soundEnabled: value);
  }

  Future<void> loadDeviceInfo() async {
    state = state.copyWith(isLoadingDeviceInfo: true);
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.getMap('/api/devices/my-info');
      final info = DeviceInfoData.fromJson(response);
      state = state.copyWith(deviceInfo: info, isLoadingDeviceInfo: false);
    } catch (e) {
      state = state.copyWith(deviceInfo: null, isLoadingDeviceInfo: false);
    }
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(settingsProvider.notifier).loadDeviceInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Section
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: AppTheme.linearGradient(),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        (user?.displayName ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Unknown',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${user?.username ?? ''}',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 14,
                          ),
                        ),
                        if (user?.bio != null &&
                            user!.bio!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            user.bio!,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Device Info Section
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.computer_rounded,
                          size: 20, color: AppTheme.primaryIndigo),
                      const SizedBox(width: 8),
                      const Text(
                        'Device Information',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (settings.isLoadingDeviceInfo)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryIndigo,
                          ),
                        ),
                      ),
                    )
                  else if (settings.deviceInfo != null) ...[
                    _buildInfoRow(
                        Icons.desktop_windows_rounded, 'Machine Name',
                        settings.deviceInfo!.deviceName),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                        Icons.info_rounded, 'OS',
                        settings.deviceInfo!.platform),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                        Icons.devices_rounded, 'Model',
                        settings.deviceInfo!.deviceModel),
                    if (settings.deviceInfo!.ipAddress != null) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(
                          Icons.wifi_rounded, 'IP Address',
                          settings.deviceInfo!.ipAddress!),
                    ],
                  ] else
                    const Text(
                      'Device info unavailable. Make sure the backend is running.',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 13),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Server Configuration
          const Text(
            'Server Configuration',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Server URL',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: TextField(
                      controller: TextEditingController(
                          text: settings.serverUrl),
                      decoration: const InputDecoration(
                        hintText: 'http://localhost:5000',
                        hintStyle:
                            TextStyle(color: AppTheme.textMuted),
                        prefixIcon: Icon(Icons.link_rounded,
                            color: AppTheme.textMuted, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      style: const TextStyle(
                          color: AppTheme.textPrimary),
                      onSubmitted: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .setServerUrl(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Appearance
          const Text(
            'Appearance',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Dark Theme',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15)),
                  subtitle: const Text(
                    'Use dark color scheme',
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                  value: settings.isDarkMode,
                  activeThumbColor: AppTheme.primaryIndigo,
                  activeTrackColor:
                      AppTheme.primaryIndigo.withValues(alpha: 0.3),
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .toggleDarkMode(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Notification Preferences
          const Text(
            'Notifications',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Push Notifications',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15)),
                  subtitle: const Text(
                    'Receive push notifications',
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                  value: settings.notificationsEnabled,
                  activeThumbColor: AppTheme.primaryIndigo,
                  activeTrackColor:
                      AppTheme.primaryIndigo.withValues(alpha: 0.3),
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .toggleNotifications(value);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Message Sounds',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15)),
                  subtitle: const Text(
                    'Play sound on new messages',
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                  value: settings.soundEnabled,
                  activeThumbColor: AppTheme.primaryIndigo,
                  activeTrackColor:
                      AppTheme.primaryIndigo.withValues(alpha: 0.3),
                  onChanged: (value) {
                    ref
                        .read(settingsProvider.notifier)
                        .toggleSound(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Logout
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppTheme.linearGradient(),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppTheme.surface,
                      title: const Text('Logout',
                          style:
                              TextStyle(color: AppTheme.textPrimary)),
                      content: const Text(
                          'Are you sure you want to logout?',
                          style: TextStyle(
                              color: AppTheme.textSecondary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppTheme.linearGradient(),
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: TextButton(
                            onPressed: () {
                              ref
                                  .read(authStateProvider.notifier)
                                  .logout();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Logout',
                                style:
                                    TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // App info
          Center(
            child: Column(
              children: [
                const Text(
                  'OmniConnect v1.0.0',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connected to ${settings.serverUrl}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
