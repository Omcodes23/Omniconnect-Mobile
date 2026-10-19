import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/message.dart';
import '../../../services/auth_provider.dart';
import '../../../services/chat_provider.dart';
import '../../../services/notification_provider.dart';
import '../../../services/device_provider.dart';
import '../../../services/routing_provider.dart';
import '../../../services/signalr_service.dart';
import '../../calls/presentation/call_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedFriendId;
  String? _selectedFriendName;
  bool _selectedFriendIsInternet = false;
  final _quickMessageController = TextEditingController();
  final _searchController = TextEditingController();
  Timer? _deviceRefreshTimer;
  String _currentDeviceId = 'mobile-device';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(chatProvider.notifier).loadAll();
      ref.read(notificationProvider.notifier).loadNotifications();

      final api = ref.read(apiServiceProvider);
      final token = api.token;
      if (token != null && token.isNotEmpty) {
        final signalR = ref.read(signalRServiceProvider);
        signalR.onMessageReceived = (data) {
          try {
            final msg = MessageDto.fromJson(data);
            ref.read(chatProvider.notifier).addReceivedMessage(msg);
          } catch (_) {}
        };
        signalR.onIncomingCall = (data) {
          if (!mounted) return;
          try {
            final callerId = data['callerId']?.toString() ?? '';
            final callerName = data['callerName']?.toString() ?? 'Incoming Call';
            final avatarUrl = data['callerAvatar']?.toString();
            final isVideo = (data['type']?.toString().toLowerCase() == 'video');
            final callId = data['id']?.toString();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  callData: CallData(
                    userId: callerId,
                    userName: callerName,
                    avatarUrl: avatarUrl,
                    isVideoCall: isVideo,
                    callId: callId,
                  ),
                  isIncoming: true,
                ),
              ),
            );
          } catch (_) {}
        };
        await signalR.connect(api.baseUrl, token);
      }

      final devId = await DeviceListNotifier.getPersistentDeviceId();
      if (mounted) {
        setState(() {
          _currentDeviceId = devId;
        });
        final authState = ref.read(authStateProvider);
        final displayName = authState.user?.displayName ?? 'Mobile User';
        await ref.read(deviceListProvider.notifier).registerThisDevice(
              deviceId: devId,
              deviceName: 'Mobile ($displayName)',
              deviceModel: 'Android',
            );
        ref.read(deviceListProvider.notifier).loadDevices();
        ref.read(routingProvider.notifier).loadRoutes();
      }
    });

    _deviceRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.read(deviceListProvider.notifier).loadDevices();
        ref.read(routingProvider.notifier).loadRoutes();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quickMessageController.dispose();
    _searchController.dispose();
    _deviceRefreshTimer?.cancel();
    super.dispose();
  }

  String _deviceId() {
    return _currentDeviceId;
  }

  void _sendQuickMessage() {
    final text = _quickMessageController.text.trim();
    if (text.isEmpty || _selectedFriendId == null) return;
    ref.read(chatProvider.notifier).sendMessage(
          receiverId: _selectedFriendId!,
          content: text,
        );
    _quickMessageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final chatState = ref.watch(chatProvider);
    final notifState = ref.watch(notificationProvider);
    final isAdmin = authState.user?.username == 'admin';
    final screenWidth = MediaQuery.of(context).size.width;
    final isMasterDetail = screenWidth >= 768;

    if (isMasterDetail) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Row(
          children: [
            // Sidebar
            SizedBox(
              width: 300,
              child: _buildSidebar(authState, chatState, notifState, isAdmin, isMasterDetail: true),
            ),
            // Divider
            const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderSubtle),
            // Master-detail right viewport
            Expanded(
              child: _selectedFriendId == null
                  ? _buildEmptyState()
                  : _buildInlineChat(authState),
            ),
          ],
        ),
      );
    }

    // Mobile single-pane layout
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: const Center(
                child: Text(
                  'OC',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              authState.user?.displayName ?? 'OmniConnect',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: notifState.unreadCount > 0,
              label: Text('${notifState.unreadCount}'),
              child: const Icon(Icons.notifications_outlined, size: 20),
            ),
            onPressed: () => context.push('/notifications'),
            tooltip: 'Notifications',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryBlue,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Friends (${chatState.friends.length})'),
            Tab(text: 'Internet hosts'),
            const Tab(text: 'Devices'),
          ],
        ),
      ),
      drawer: _buildAppDrawer(authState, isAdmin),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsList(chatState, authState, isMasterDetail: false),
          _buildInternetHostsList(),
          _buildNearbyDevices(isMasterDetail: false),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textMuted,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: 'Chats',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome_rounded),
            label: 'AI Chat',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.hub_outlined),
            label: 'Mesh',
          ),
          if (isAdmin)
            const BottomNavigationBarItem(
              icon: Icon(Icons.admin_panel_settings_outlined),
              label: 'Admin',
            ),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              break;
            case 1:
              context.push('/ai');
              break;
            case 2:
              context.push('/network'); // Mesh
              break;
            case 3:
              // Admin only if needed; removed Files redirect
              if (isAdmin) context.push('/admin');
              break;
            case 4:
              if (isAdmin) context.push('/admin');
              break;
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Drawer
  // ---------------------------------------------------------------------------
  Widget _buildAppDrawer(AuthState authState, bool isAdmin) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Center(
                        child: Text(
                          (authState.user?.displayName.isNotEmpty == true)
                              ? authState.user!.displayName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authState.user?.displayName ?? 'User',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppTheme.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Online',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryBlue),
            title: const Text('AI Assistant', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              context.push('/ai');
            },
          ),
          ListTile(
            leading: const Icon(Icons.hub_outlined, color: AppTheme.success),
            title: const Text('Network Mesh', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              context.push('/network');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary),
            title: const Text('Settings', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              context.push('/settings');
            },
          ),
          if (isAdmin)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined, color: AppTheme.warning),
              title: const Text('Admin Panel', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                context.push('/admin');
              },
            ),
          const Divider(color: AppTheme.borderSubtle),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppTheme.error),
            title: const Text('Sign Out', style: TextStyle(color: AppTheme.error)),
            onTap: () {
              ref.read(authStateProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sidebar (Master-detail layout)
  // ---------------------------------------------------------------------------
  Widget _buildSidebar(
    AuthState authState,
    ChatState chatState,
    NotificationState notifState,
    bool isAdmin, {
    required bool isMasterDetail,
  }) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.borderSubtle, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          (authState.user?.displayName.isNotEmpty == true)
                              ? authState.user!.displayName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.surface, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authState.user?.displayName ?? 'User',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Online',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.admin_panel_settings_outlined,
                        size: 18, color: AppTheme.warning),
                    onPressed: () => context.push('/admin'),
                    tooltip: 'Admin Panel',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search contacts, channels...',
                prefixIcon: Icon(Icons.search_rounded, size: 16, color: AppTheme.textMuted),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            ),
          ),
          // Tab bar
          TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.primaryBlue,
            labelColor: AppTheme.primaryBlue,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Friends'),
              Tab(text: 'Internet'),
              Tab(text: 'Devices'),
            ],
          ),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsList(chatState, authState, isMasterDetail: isMasterDetail),
                _buildInternetHostsList(),
                _buildNearbyDevices(isMasterDetail: isMasterDetail),
              ],
            ),
          ),
          // Bottom Quick Actions
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Column(
              children: [
                _SidebarActionTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'AI Assistant',
                  onTap: () => context.push('/ai'),
                ),
                _SidebarActionTile(
                  icon: Icons.hub_outlined,
                  label: 'Network Mesh',
                  onTap: () => context.push('/network'),
                ),
                _SidebarActionTile(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Friends List
  // ---------------------------------------------------------------------------
  Widget _buildFriendsList(
    ChatState chatState,
    AuthState authState, {
    required bool isMasterDetail,
  }) {
    if (chatState.friends.isEmpty) {
      return const Center(
        child: Text(
          'No friends yet',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: chatState.friends.length,
      itemBuilder: (context, i) {
        final friend = chatState.friends[i];
        final isSelected = _selectedFriendId == friend.id;
        final isOnline = friend.status == 'Online';
        // All loaded friends are Internet friendships; the AI node is never
        // callable.
        final canCall =
            friend.id.isNotEmpty && friend.id != AppConstants.aiAssistantUserId;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            leading: Stack(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Center(
                    child: Text(
                      friend.displayName.isNotEmpty ? friend.displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              friend.displayName,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              friend.status,
              style: TextStyle(
                color: isOnline ? AppTheme.success : AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canCall) ...[
                  IconButton(
                    icon: const Icon(Icons.phone_rounded, color: AppTheme.textSecondary, size: 16),
                    onPressed: () {
                      context.push(
                        '/call/${friend.id}?name=${Uri.encodeComponent(friend.displayName)}&type=audio',
                      );
                    },
                    tooltip: 'Voice Call',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.videocam_rounded, color: AppTheme.textSecondary, size: 16),
                    onPressed: () {
                      context.push(
                        '/call/${friend.id}?name=${Uri.encodeComponent(friend.displayName)}&type=video',
                      );
                    },
                    tooltip: 'Video Call',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
            onTap: () {
              if (isMasterDetail) {
                setState(() {
                  _selectedFriendId = friend.id;
                  _selectedFriendName = friend.displayName;
                  _selectedFriendIsInternet = true;
                });
                ref.read(chatProvider.notifier).loadMessages(friend.id);
              } else {
                context.push(
                  '/chat/${friend.id}?name=${Uri.encodeComponent(friend.displayName)}&internet=true',
                );
              }
            },
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Internet hosts List
  // ---------------------------------------------------------------------------
  Widget _buildCommunitiesList(ChatState chatState) {
    if (chatState.communities.isEmpty) {
      return const Center(
        child: Text(
          'No communities yet',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: chatState.communities.length,
      itemBuilder: (context, i) {
        final comm = chatState.communities[i];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: const Center(
                child: Text(
                  '#',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(
              comm.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${comm.memberCount} members',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
            ),
            onTap: () {},
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Internet Hosts (authenticated backend-registered users)
  // ---------------------------------------------------------------------------
  Widget _buildInternetHostsList() {
    final deviceState = ref.watch(deviceListProvider);
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState.user?.id;
    final hosts = deviceState.devices
        .where((d) => d.userId != null && d.userId != currentUserId && d.isChattable)
        .toList();

    if (hosts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No online hosts', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: hosts.length,
      itemBuilder: (context, i) {
        final d = hosts[i];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryBlue,
              child: Text(
                (d.userName ?? d.deviceName)[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            title: Text(
              d.userName ?? d.deviceName,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text('Online via Internet', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
            trailing: ElevatedButton(
              onPressed: () {
                if (d.userId != null) {
                  ref.read(chatProvider.notifier).ensureFriend(d.userId!);
                  context.push('/chat/${d.userId}?name=${Uri.encodeComponent(d.userName ?? d.deviceName)}&internet=true');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
              child: const Text('Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Nearby Devices
  // ---------------------------------------------------------------------------
  Widget _buildNearbyDevices({required bool isMasterDetail}) {
    final deviceState = ref.watch(deviceListProvider);
    final routingState = ref.watch(routingProvider);

    if (deviceState.isLoading && deviceState.devices.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
      );
    }

    if (deviceState.devices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.devices_other_rounded, size: 36, color: AppTheme.textMuted),
              SizedBox(height: 8),
              Text(
                'No nearby devices',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text(
                'Connect devices to the same LAN or mesh',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      itemCount: deviceState.devices.length,
      itemBuilder: (context, i) {
        final d = deviceState.devices[i];
        final route = routingState.routeFor(d.deviceId);
        final visibleTransports = d.availableTransports.where((t) => t == 'LAN' || t == 'Bluetooth').toList();
        final transportDetail = visibleTransports.isNotEmpty
            ? visibleTransports.join(', ')
            : (route != null && route.isAvailable
                ? '${route.activeTransport} · ${route.latencyMs.toStringAsFixed(0)}ms'
                : (route?.activeTransport ?? 'LAN'));

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: const Icon(
                  Icons.laptop_chromebook_rounded,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.userName ?? d.deviceName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      d.deviceModel.isNotEmpty ? d.deviceModel : d.platform,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            transportDetail,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (d.isChattable)
                ElevatedButton(
                  onPressed: () {
                    // Prefer a fresh ephemeral direct (LAN/Bluetooth) session when the
                    // peer has a reachable IP + port — no DB history is loaded.
                    final canDirect = d.ipAddress != null && d.ipAddress!.isNotEmpty && d.port > 0;
                    if (canDirect || (d.deviceName != null && d.deviceName!.contains('om')) || d.availableTransports?.contains('LAN') == true) {
                      final usePort = d.port > 0 ? d.port : 5001;
                      final useIp = d.ipAddress ?? '192.168.29.27';
                      context.push(
                        '/direct-chat?peerId=${Uri.encodeComponent(d.deviceId)}'
                        '&peerIp=${Uri.encodeComponent(useIp)}'
                        '&peerPort=${usePort}'
                        '&peerName=${Uri.encodeComponent(d.userName ?? d.deviceName)}'
                        '&selfPeerId=${Uri.encodeComponent(_currentDeviceId)}',
                      );
                      return;
                    }
                    if (d.userId != null) {
                      ref.read(chatProvider.notifier).ensureFriend(d.userId!);
                    }
                    final isInternetDevice =
                        d.availableTransports.contains('Internet');
                    if (isMasterDetail) {
                      setState(() {
                        _selectedFriendId = d.userId;
                        _selectedFriendName = d.userName ?? d.deviceName;
                        _selectedFriendIsInternet = isInternetDevice;
                      });
                      if (d.userId != null) {
                        ref.read(chatProvider.notifier).loadMessages(d.userId!);
                      }
                    } else {
                      context.push(
                        '/chat/${d.userId}?name=${Uri.encodeComponent(d.userName ?? d.deviceName)}'
                        '${isInternetDevice ? '&internet=true' : ''}',
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Empty State (Master-Detail)
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 28,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select a conversation',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose a friend, community, or device to start chatting',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inline Chat (Master-Detail)
  // ---------------------------------------------------------------------------
  Widget _buildInlineChat(AuthState authState) {
    final chatState = ref.watch(chatProvider);
    final currentUserId = authState.user?.id ?? '';

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Center(
                  child: Text(
                    (_selectedFriendName ?? '?')[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedFriendName ?? 'User',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      'Online',
                      style: TextStyle(color: AppTheme.success, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (_selectedFriendIsInternet &&
                  _selectedFriendId != null &&
                  _selectedFriendId != AppConstants.aiAssistantUserId) ...[
                IconButton(
                  icon: const Icon(Icons.phone_rounded, color: AppTheme.textSecondary, size: 18),
                  onPressed: () {
                    context.push(
                      '/call/$_selectedFriendId?name=${Uri.encodeComponent(_selectedFriendName ?? 'User')}&type=audio',
                    );
                  },
                  tooltip: 'Voice Call',
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_rounded, color: AppTheme.textSecondary, size: 18),
                  onPressed: () {
                    context.push(
                      '/call/$_selectedFriendId?name=${Uri.encodeComponent(_selectedFriendName ?? 'User')}&type=video',
                    );
                  },
                  tooltip: 'Video Call',
                ),
              ],
            ],
          ),
        ),
        // Messages
        Expanded(
          child: chatState.isLoading
              ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
                )
              : chatState.messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet\nSay hello!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: chatState.messages.length,
                      itemBuilder: (context, index) {
                        final msg = chatState.messages[index];
                        final isMe = msg.senderId == currentUserId;
                        return _inlineMessageBubble(msg, isMe);
                      },
                    ),
        ),
        // Input Area
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickMessageController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  onSubmitted: (_) => _sendQuickMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: AppTheme.primaryBlue),
                onPressed: _sendQuickMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _inlineMessageBubble(dynamic message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primaryBlue : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: isMe ? null : Border.all(color: AppTheme.borderSubtle),
        ),
        child: Text(
          message.content ?? '',
          style: TextStyle(
            color: isMe ? Colors.white : AppTheme.textPrimary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _SidebarActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
