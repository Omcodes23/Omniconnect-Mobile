import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/notification_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Notifications',
                style: TextStyle(color: AppTheme.textPrimary)),
            if (state.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${state.unreadCount}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () {
                ref
                    .read(notificationProvider.notifier)
                    .markAllAsRead();
              },
              child: const Text('Mark all read'),
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
          : state.notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 64,
                          color: AppTheme.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'No notifications yet',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(4),
                  itemCount: state.notifications.length,
                  itemBuilder: (context, index) {
                    final notification = state.notifications[index];
                    final timeStr = DateFormat('MMM d, HH:mm')
                        .format(notification.createdAt);

                    IconData icon;
                    Color iconColor;
                    switch (notification.type) {
                      case 'message':
                        icon = Icons.message_rounded;
                        iconColor = AppTheme.secondary;
                        break;
                      case 'friend_request':
                        icon = Icons.person_add_rounded;
                        iconColor = AppTheme.success;
                        break;
                      case 'call':
                        icon = Icons.phone_rounded;
                        iconColor = AppTheme.primaryPurple;
                        break;
                      case 'system':
                        icon = Icons.info_rounded;
                        iconColor = AppTheme.warning;
                        break;
                      default:
                        icon = Icons.notifications_rounded;
                        iconColor = AppTheme.primaryIndigo;
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: notification.isRead
                            ? AppTheme.surface
                            : AppTheme.surfaceElevated
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: !notification.isRead
                            ? Border.all(
                                color: AppTheme.primaryIndigo
                                    .withValues(alpha: 0.25),
                                width: 1)
                            : Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.04)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              iconColor.withValues(alpha: 0.12),
                          child: Icon(icon,
                              color: iconColor, size: 20),
                        ),
                        title: Text(
                          notification.title,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: notification.isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notification.body,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        trailing: notification.isRead
                            ? null
                            : Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryIndigo,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        onTap: () {
                          if (!notification.isRead) {
                            ref
                                .read(notificationProvider.notifier)
                                .markAsRead(notification.id);
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
