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
  void Function(String userId)? onUserOnline;
  void Function(String userId)? onUserOffline;

  SignalRService({
    this.onMessageReceived,
    this.onIncomingCall,
    this.onCallAccepted,
    this.onCallRejected,
    this.onCallEnded,
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

  Future<void> disconnect() async {
    try {
      await _connection?.stop();
    } catch (_) {}
    _connection = null;
  }
}
