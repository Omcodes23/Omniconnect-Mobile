import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/files/presentation/files_screen.dart';
import '../../features/ai/presentation/ai_chat_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/network/presentation/network_graph_screen.dart';
import '../../features/network/presentation/direct_chat_screen.dart';
import '../../features/calls/presentation/call_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.status == AuthStatus.authenticated;
      final isLoginRoute = state.uri.toString() == '/login';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/chat/:userId',
        builder: (context, state) => ChatScreen(
          userId: state.pathParameters['userId'] ?? '',
          userName: state.uri.queryParameters['name'],
          isInternet: state.uri.queryParameters['internet'] == 'true',
        ),
      ),
      GoRoute(
        path: '/channel/:communityId/:channelId',
        builder: (context, state) => const ChatScreen(
          userId: '',
        ),
      ),
      GoRoute(
        path: '/call/:userId',
        builder: (context, state) => CallScreen(
          callData: CallData(
            userId: state.pathParameters['userId'] ?? '',
            userName: state.uri.queryParameters['name'] ?? 'User',
            isVideoCall: state.uri.queryParameters['type'] == 'video',
            callId: state.uri.queryParameters['callId'],
          ),
          isIncoming: state.uri.queryParameters['incoming'] == 'true',
        ),
      ),
      GoRoute(
        path: '/files',
        builder: (context, state) => const FilesScreen(),
      ),
      GoRoute(
        path: '/ai',
        builder: (context, state) => const AiChatScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/network',
        builder: (context, state) => const NetworkGraphScreen(),
      ),
      GoRoute(
        path: '/direct-chat',
        builder: (context, state) => DirectChatScreen(
          peerId: state.uri.queryParameters['peerId'] ?? '',
          peerIp: state.uri.queryParameters['peerIp'] ?? '',
          peerPort: int.tryParse(state.uri.queryParameters['peerPort'] ?? '') ?? 5001,
          peerName: state.uri.queryParameters['peerName'] ?? 'Peer',
          selfPeerId: state.uri.queryParameters['selfPeerId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});