import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_core/signalr_core.dart';

final signalRServiceProvider = Provider<SignalRService>((ref) {
  return SignalRService();
});

class SignalRService {
  HubConnection? _connection;

  void Function(Map<String, dynamic> message)? onMessageReceived;
  void Function(Map<String, dynamic> call)? onIncomingCall;
  void Function(Map<String, dynamic> call)? onCallAccepted;
  void Function(Map<String, dynamic> call)? onCallRejected;
  void Function(Map<String, dynamic> call)? onCallEnded;
  void Function(String senderId, String kind, String payload)? onCallMediaReceived;
  void Function(String userId)? onUserOnline;
  void Function(String userId)? onUserOffline;

  SignalRService({
    this.onMessageReceived,
    this.onIncomingCall,
    this.onCallAccepted,
    this.onCallRejected,
    this.onCallEnded,
    this.onCallMediaReceived,
    this.onUserOnline,
    this.onUserOffline,
  });

  bool get isConnected => _connection?.state == HubConnectionState.connected;

  Future<void> connect(String baseUrl, String token) async {
    if (_connection != null && _connection?.state == HubConnectionState.connected) {
      return;
    }

    try {
      final hubUrl = '$baseUrl/hubs/chat';
      _connection = HubConnectionBuilder()
          .withUrl(
            hubUrl,
            HttpConnectionOptions(
              accessTokenFactory: () async => token,
              logging: (level, message) => debugPrint('SignalR: $message'),
            ),
          )
          .withAutomaticReconnect([0, 2000, 10000, 30000])
          .build();

      _connection?.on('MessageReceived', (args) {
        if (args != null && args.isNotEmpty && args[0] is Map<String, dynamic>) {
          onMessageReceived?.call(args[0] as Map<String, dynamic>);
        }
      });

      _connection?.on('IncomingCall', (args) {
        if (args != null && args.isNotEmpty && args[0] is Map<String, dynamic>) {
          onIncomingCall?.call(args[0] as Map<String, dynamic>);
        }
      });

      _connection?.on('CallAccepted', (args) {
        if (args != null && args.isNotEmpty && args[0] is Map<String, dynamic>) {
          onCallAccepted?.call(args[0] as Map<String, dynamic>);
        }
      });

      _connection?.on('CallRejected', (args) {
        if (args != null && args.isNotEmpty && args[0] is Map<String, dynamic>) {
          onCallRejected?.call(args[0] as Map<String, dynamic>);
        }
      });

      _connection?.on('CallEnded', (args) {
        if (args != null && args.isNotEmpty && args[0] is Map<String, dynamic>) {
          onCallEnded?.call(args[0] as Map<String, dynamic>);
        }
      });

      _connection?.on('CallMediaReceived', (args) {
        if (args != null && args.length >= 3) {
          final senderId = args[0]?.toString() ?? '';
          final kind = args[1]?.toString() ?? '';
          final payload = args[2]?.toString() ?? '';
          if (senderId.isNotEmpty && kind.isNotEmpty && payload.isNotEmpty) {
            onCallMediaReceived?.call(senderId, kind, payload);
          }
        }
      });

      _connection?.on('UserOnline', (args) {
        if (args != null && args.isNotEmpty && args[0] is String) {
          onUserOnline?.call(args[0] as String);
        }
      });

      _connection?.on('UserOffline', (args) {
        if (args != null && args.isNotEmpty && args[0] is String) {
          onUserOffline?.call(args[0] as String);
        }
      });

      await _connection?.start();
    } catch (e) {
      debugPrint('SignalR connection failed: $e');
    }
  }

  Future<void> sendCallMedia(
    String targetUserId,
    String kind,
    String payload,
  ) async {
    final connection = _connection;
    if (connection == null ||
        connection.state != HubConnectionState.connected) {
      return;
    }
    try {
      await connection.invoke(
        'SendCallMedia',
        args: <dynamic>[targetUserId, kind, payload],
      );
    } catch (e) {
      debugPrint('sendCallMedia failed: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.stop();
    } catch (_) {}
    _connection = null;
  }
}
