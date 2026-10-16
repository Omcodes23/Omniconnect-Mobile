import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? data;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.type = 'info',
    this.isRead = false,
    required this.createdAt,
    this.data,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: json['id']?.toString() ?? '',
        title: json['title'] ?? '',
        body: json['body'] ?? '',
        type: json['type'] ?? 'info',
        isRead: json['isRead'] ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        data: json['data'] as Map<String, dynamic>?,
      );
}

class NotificationState {
  final List<NotificationItem> notifications;
  final bool isLoading;
  final String? error;
  final int unreadCount;

  const NotificationState({
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.unreadCount = 0,
  });

  NotificationState copyWith({
    List<NotificationItem>? notifications,
    bool? isLoading,
    String? error,
    int? unreadCount,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class NotificationNotifier extends Notifier<NotificationState> {
  @override
  NotificationState build() => const NotificationState();

  Future<void> loadNotifications() async {
    state = state.copyWith(isLoading: true);
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/notifications');
      final notifications = data
          .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final unread = notifications.where((n) => !n.isRead).length;
      state = state.copyWith(
        notifications: notifications,
        unreadCount: unread,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load notifications: $e');
    }
  }

  Future<void> markAsRead(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/notifications/$id/read', null);
      final updated = state.notifications.map((n) {
        if (n.id == id) {
          return NotificationItem(
            id: n.id,
            title: n.title,
            body: n.body,
            type: n.type,
            isRead: true,
            createdAt: n.createdAt,
            data: n.data,
          );
        }
        return n;
      }).toList();
      final unread = updated.where((n) => !n.isRead).length;
      state = state.copyWith(notifications: updated, unreadCount: unread);
    } catch (e) {
      state = state.copyWith(error: 'Failed to mark notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/notifications/read-all', null);
      final updated = state.notifications.map((n) {
        return NotificationItem(
          id: n.id,
          title: n.title,
          body: n.body,
          type: n.type,
          isRead: true,
          createdAt: n.createdAt,
          data: n.data,
        );
      }).toList();
      state = state.copyWith(notifications: updated, unreadCount: 0);
    } catch (e) {
      state = state.copyWith(error: 'Failed to mark all as read: $e');
    }
  }
}

final notificationProvider =
    NotifierProvider<NotificationNotifier, NotificationState>(NotificationNotifier.new);