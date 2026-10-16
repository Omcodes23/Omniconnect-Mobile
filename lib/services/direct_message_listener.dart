import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A lightweight in-process HTTP listener that lets this mobile device accept
/// direct LAN messages from peers without going through the backend server.
///
/// All messages are ephemeral: kept in memory only, never written to the DB,
/// and cleared when the listener stops or a peer's message queue is drained.
class DirectMessageListener {
  static const int _defaultPort = 5001;

  final int port;
  HttpServer? _server;
  final Map<String, List<DirectMessageEntry>> _queues = {};
  bool _disposed = false;

  DirectMessageListener({this.port = _defaultPort});

  /// Start listening for direct messages on [port].
  Future<void> start() async {
    if (_disposed) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen(_onRequest);
      if (kDebugMode) {
        debugPrint('[DirectMessageListener] Listening on port $port');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DirectMessageListener] Failed to bind port $port: $e');
      }
      rethrow;
    }
  }

  /// Stop listening and clear all ephemeral queues.
  void stop() {
    _server?.close(force: true);
    _server = null;
    _queues.clear();
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  Future<void> _onRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;

    try {
      final path = request.uri.path;

      // ── POST /api/direct/message ── store ephemeral message
      if (path == '/api/direct/message' && request.method == 'POST') {
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final toPeerId = json['toPeerId']?.toString() ?? '';
        if (toPeerId.isEmpty) {
          response.statusCode = 400;
          response.close();
          return;
        }

        final entry = DirectMessageEntry(
          fromPeerId: json['fromPeerId']?.toString() ?? 'Peer',
          fromPeerName: json['fromPeerName']?.toString() ?? 'Peer',
          content: json['content']?.toString() ?? '',
          type: json['type']?.toString() ?? 'Text',
          clientMessageId: json['clientMessageId']?.toString(),
          sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '') ?? DateTime.now(),
        );

        _queues.putIfAbsent(toPeerId, () => []).add(entry);

        response.statusCode = 200;
        response.write(jsonEncode({'ok': true}));
        response.close();
        return;
      }

      // ── GET /api/direct/messages/{peerId} ── drain ephemeral queue
      if (path.startsWith('/api/direct/messages/') && request.method == 'GET') {
        final peerId = path.substring('/api/direct/messages/'.length);
        final queue = _queues.putIfAbsent(peerId, () => []);
        final snapshot = List<DirectMessageEntry>.from(queue);
        queue.clear();

        response.statusCode = 200;
        response.write(jsonEncode(snapshot
            .map((e) => e.toJson())
            .toList()));
        response.close();
        return;
      }

      // ── GET /api/direct/health ──
      if (path == '/api/direct/health') {
        response.statusCode = 200;
        response.write(jsonEncode({'ok': true}));
        response.close();
        return;
      }

      response.statusCode = 404;
      response.close();
    } catch (_) {
      try {
        response.statusCode = 500;
        response.close();
      } catch (_) {}
    }
  }

  /// Drain queued messages for [peerId] from this device's local listener.
  List<DirectMessageEntry> fetchQueued({required String peerId}) {
    final queue = _queues.putIfAbsent(peerId, () => []);
    final snapshot = List<DirectMessageEntry>.from(queue);
    queue.clear();
    return snapshot;
  }

  /// Send a direct message to a peer's listener over LAN.
  static Future<bool> send({
    required String peerIp,
    required int peerPort,
    required String fromPeerId,
    required String fromPeerName,
    required String toPeerId,
    required String content,
    String type = 'Text',
  }) async {
    try {
      final body = jsonEncode({
        'fromPeerId': fromPeerId,
        'fromPeerName': fromPeerName,
        'toPeerId': toPeerId,
        'content': content,
        'type': type,
        'clientMessageId': DateTime.now().millisecondsSinceEpoch.toString(),
        'sentAt': DateTime.now().toUtc().toIso8601String(),
      });
      final request = await HttpClient()
        .postUrl(Uri.parse('http://$peerIp:$peerPort/api/direct/message'))
        .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(body));
      final clientResponse = await request.close();
      return clientResponse.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch (and drain) ephemeral direct messages from a peer's listener.
  static Future<List<DirectMessageEntry>> fetch({
    required String peerIp,
    required int peerPort,
    required String peerId,
  }) async {
    try {
      final response = await HttpClient()
          .getUrl(Uri.parse(
              'http://$peerIp:$peerPort/api/direct/messages/${Uri.encodeComponent(peerId)}'))
          .timeout(const Duration(seconds: 5));
      final clientResponse = await response.close();
      if (clientResponse.statusCode != 200) return const [];
      final body = await clientResponse.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(DirectMessageEntry.fromJson)
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Quickly check whether a peer's direct listener is reachable.
  static Future<bool> isReachable({
    required String peerIp,
    required int peerPort,
  }) async {
    try {
      final response = await HttpClient()
          .getUrl(Uri.parse('http://$peerIp:$peerPort/api/direct/health'))
          .timeout(const Duration(seconds: 2));
      final clientResponse = await response.close();
      return clientResponse.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Ephemeral in-memory message entry (never written to DB).
class DirectMessageEntry {
  final String fromPeerId;
  final String fromPeerName;
  final String content;
  final String type;
  final String? clientMessageId;
  final DateTime sentAt;

  DirectMessageEntry({
    required this.fromPeerId,
    required this.fromPeerName,
    required this.content,
    this.type = 'Text',
    this.clientMessageId,
    required this.sentAt,
  });

  factory DirectMessageEntry.fromJson(Map<String, dynamic> json) =>
      DirectMessageEntry(
        fromPeerId: json['fromPeerId']?.toString() ?? '',
        fromPeerName: json['fromPeerName']?.toString() ?? 'Peer',
        content: json['content']?.toString() ?? '',
        type: json['type']?.toString() ?? 'Text',
        clientMessageId: json['clientMessageId']?.toString(),
        sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'fromPeerId': fromPeerId,
        'fromPeerName': fromPeerName,
        'content': content,
        'type': type,
        'clientMessageId': clientMessageId,
        'sentAt': sentAt.toUtc().toIso8601String(),
      };
}
