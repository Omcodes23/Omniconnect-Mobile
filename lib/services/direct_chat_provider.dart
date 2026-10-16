import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'auth_provider.dart';
import 'bluetooth_service.dart';
import 'direct_message_listener.dart';

class DirectMessageItem {
  final String fromPeerId;
  final String fromPeerName;
  final String content;
  final String type;
  final String? clientMessageId;
  final DateTime sentAt;
  final bool isMe;
  final String transport; // 'LAN' | 'Bluetooth'

  DirectMessageItem({
    required this.fromPeerId,
    required this.fromPeerName,
    required this.content,
    this.type = 'Text',
    this.clientMessageId,
    required this.sentAt,
    required this.isMe,
    this.transport = 'LAN',
  });
}

class DirectChatState {
  final List<DirectMessageItem> messages;
  final bool isLoading;
  final String? error;
  final String? transport; // 'LAN' | 'Bluetooth' | null
  final bool bluetoothAvailable;

  const DirectChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.transport,
    this.bluetoothAvailable = false,
  });

  DirectChatState copyWith({
    List<DirectMessageItem>? messages,
    bool? isLoading,
    String? error,
    String? transport,
    bool? bluetoothAvailable,
  }) {
    return DirectChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      transport: transport ?? this.transport,
      bluetoothAvailable: bluetoothAvailable ?? this.bluetoothAvailable,
    );
  }
}

class DirectChatNotifier extends Notifier<DirectChatState> {
  String? _peerId;
  String? _peerIp;
  int _peerPort = DirectMessageListener().port;
  String _peerName = '';
  String _selfPeerId = '';
  String _transport = 'LAN'; // 'LAN' | 'Bluetooth'
  Timer? _pollTimer;
  Timer? _btPollTimer;
  bool _disposed = false;
  late final BluetoothService _bt;
  bool _btAvailable = false;

  @override
  DirectChatState build() {
    _bt = BluetoothService();
    return const DirectChatState();
  }

  /// Start a brand-new ephemeral direct chat session with a peer.
  /// History is cleared — each session starts fresh (no DB).
  /// [transport] is 'LAN' or 'Bluetooth'. Bluetooth is only used when
  /// the platform actually reports a working RFCOMM path.
  void startSession({
    required String peerId,
    required String peerIp,
    required int peerPort,
    required String peerName,
    required String selfPeerId,
    String transport = 'LAN',
  }) {
    _disposed = false;
    _peerId = peerId;
    _peerIp = peerIp;
    _peerPort = peerPort;
    _peerName = peerName;
    _selfPeerId = selfPeerId;
    _transport = transport;

    // Probe Bluetooth availability honestly; only advertise when it works.
    _btAvailable = false;
    if (transport == 'Bluetooth') {
      _btAvailable = _bt.isAvailable;
      if (!_btAvailable) {
        // Try to enable + probe once (fire-and-forget, state updated below).
        _bt.probe().then((available) {
          if (!_disposed) {
            _btAvailable = available;
            state = state.copyWith(bluetoothAvailable: available);
          }
        });
      }
    }

    // Stop old listener so port 5001 is free
    try { ref.read(directMessageListenerProvider).stop(); } catch (_) {}

    state = DirectChatState(transport: transport, bluetoothAvailable: _btAvailable);

    // Stop any previous timers.
    _pollTimer?.cancel();
    _btPollTimer?.cancel();

    if (_transport == 'Bluetooth') {
      // Start our RFCOMM server so the peer can reach us back.
      _bt.startServer().catchError((_) => false);
      _startBluetoothPolling();
    } else {
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _poll();
  }

  void _startBluetoothPolling() {
    _btPollTimer?.cancel();
    _btPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollBluetooth());
    _pollBluetooth();

    // Listen for inbound Bluetooth messages pushed from the platform channel.
    _bt.onMessageReceived.listen((msg) {
      if (_disposed) return;
      if (_transport != 'Bluetooth') return;
      _appendIncoming(
        fromPeerId: msg.deviceId,
        fromPeerName: msg.fromPeerName ?? 'Peer',
        content: msg.content,
        clientMessageId: msg.clientMessageId,
        sentAt: msg.timestamp,
        transport: 'Bluetooth',
      );
    });
  }

  Future<void> _poll() async {
    if (_disposed || _peerIp == null || _peerId == null) return;

    final api = ref.read(apiServiceProvider);
    final reachable = await api.isDirectPeerReachable(
      peerIp: _peerIp!,
      peerPort: _peerPort,
    );
    if (!reachable) return;

    // Drain our OWN listener queue (messages pushed here by peer POST)
    final listener = ref.read(directMessageListenerProvider);
    final entries = listener.fetchQueued(peerId: _selfPeerId);
    final newMessages = entries.where((e) {
      final id = e.clientMessageId?.toString();
      return !state.messages.any(
        (m) => m.content == e.content &&
            id != null &&
            m.fromPeerId == id,
      );
    }).toList();

    if (newMessages.isNotEmpty) {
      final msgs = <DirectMessageItem>[
        ...state.messages,
        ...newMessages.reversed.map((e) => DirectMessageItem(
          fromPeerId: e.fromPeerId ?? '',
          fromPeerName: e.fromPeerName ?? 'Peer',
          content: e.content ?? '',
          type: e.type ?? 'Text',
          clientMessageId: e.clientMessageId,
          sentAt: e.sentAt,
          isMe: e.fromPeerId == _selfPeerId,
          transport: 'LAN',
        )),
      ];
      state = state.copyWith(messages: msgs, transport: 'LAN');
    }
  }

  Future<void> _pollBluetooth() async {
    if (_disposed || !_btAvailable) return;
    // Bluetooth inbound messages arrive via the platform channel stream above;
    // this tick keeps the transport alive and re-probes availability.
    final available = await _bt.probe();
    if (available != _btAvailable) {
      _btAvailable = available;
      state = state.copyWith(bluetoothAvailable: _btAvailable);
    }
  }

  /// Append an inbound ephemeral message (deduplicated by content+id).
  void _appendIncoming({
    required String fromPeerId,
    required String fromPeerName,
    required String content,
    String? clientMessageId,
    required DateTime sentAt,
    required String transport,
  }) {
    final already = state.messages.any((m) =>
        m.content == content &&
        m.fromPeerId == fromPeerId &&
        m.clientMessageId == clientMessageId &&
        m.transport == transport);
    if (already) return;

    state = DirectChatState(
      messages: [
        ...state.messages,
        DirectMessageItem(
          fromPeerId: fromPeerId,
          fromPeerName: fromPeerName,
          content: content,
          clientMessageId: clientMessageId,
          sentAt: sentAt,
          isMe: false,
          transport: transport,
        ),
      ],
      transport: transport,
      bluetoothAvailable: _btAvailable,
    );
  }

  /// Send a direct ephemeral message to the peer (no DB).
  /// Uses the session's transport: LAN (HTTP) or Bluetooth (RFCOMM).
  Future<bool> sendMessage(String content, {String type = 'Text'}) async {
    if (content.trim().isEmpty) return false;

    final meName = ref.read(authStateProvider).user?.displayName ?? 'Mobile User';
    final now = DateTime.now();
    final clientMsgId = now.millisecondsSinceEpoch.toString();

    if (_transport == 'Bluetooth') {
      if (!_btAvailable) return false;
      final sent = await _bt.sendMessage(
        toPeerId: _peerId ?? '',
        fromPeerId: _selfPeerId,
        fromPeerName: meName,
        content: content.trim(),
      );
      if (sent) {
        state = DirectChatState(
          messages: [
            ...state.messages,
            DirectMessageItem(
              fromPeerId: _selfPeerId,
              fromPeerName: meName,
              content: content.trim(),
              type: type,
              clientMessageId: clientMsgId,
              sentAt: now,
              isMe: true,
              transport: 'Bluetooth',
            ),
          ],
          transport: 'Bluetooth',
          bluetoothAvailable: _btAvailable,
        );
      }
      return sent;
    }

    // LAN path via HTTP.
    if (_peerIp == null || _peerId == null) return false;

    final api = ref.read(apiServiceProvider);
    final sent = await api.sendDirectMessage(
      peerIp: _peerIp!,
      peerPort: _peerPort,
      fromPeerId: _selfPeerId,
      fromPeerName: meName,
      toPeerId: _peerId!,
      content: content.trim(),
      type: type,
    );

    if (sent) {
      state = DirectChatState(
        messages: [
          ...state.messages,
          DirectMessageItem(
            fromPeerId: _selfPeerId,
            fromPeerName: meName,
            content: content.trim(),
            type: type,
            clientMessageId: clientMsgId,
            sentAt: now,
            isMe: true,
            transport: 'LAN',
          ),
        ],
        transport: 'LAN',
      );
    }

    return sent;
  }

  /// Clear the current ephemeral session without starting a new one.
  void endSession() {
    _pollTimer?.cancel();
    _btPollTimer?.cancel();
    _bt.stopServer();
    _peerId = null;
    _peerIp = null;
    _peerPort = DirectMessageListener().port;
    _peerName = '';
    _transport = 'LAN';
    _btAvailable = false;
    state = const DirectChatState();
  }

  void disposePolling() {
    _disposed = true;
    _pollTimer?.cancel();
    _btPollTimer?.cancel();
    _bt.stopServer();
    _bt.dispose();
  }
}

final directChatProvider =
    NotifierProvider<DirectChatNotifier, DirectChatState>(DirectChatNotifier.new);

final directMessageListenerProvider =
    Provider<DirectMessageListener>((ref) {
  final listener = DirectMessageListener();
  ref.onDispose(() => listener.dispose());
  return listener;
});

final bluetoothServiceProvider = Provider<BluetoothService>((ref) {
  final service = BluetoothService();
  ref.onDispose(() => service.dispose());
  return service;
});
