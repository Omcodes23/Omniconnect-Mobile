import 'dart:convert';
import 'dart:typed_data';

/// Framed Bluetooth envelope used for standalone peer-to-peer messaging.
///
/// Mirrors Desktop-Application/src/Shared/Models/BluetoothFrame.cs so Android
/// and desktop can interoperate over RFCOMM.
///
/// Frame layout (big-endian):
///   [0..1]   Magic        0x4F 0x4D ("OM")
///   [2]      Version      1
///   [3]      FrameType    0x01=Chat, 0x02=Discovery, 0x03=Ack
///   [4..5]   PayloadLen   uint16
///   [6..6+n] Payload      JSON UTF-8
///   [6+n..]  Checksum     uint16 (sum of bytes [0..6+n))
///
/// Messages are ephemeral: kept in memory only, never written to the DB.
class BluetoothFrame {
  static const int magic1 = 0x4F; // 'O'
  static const int magic2 = 0x4D; // 'M'
  static const int version = 1;

  static const int frameTypeChat = 0x01;
  static const int frameTypeDiscovery = 0x02;
  static const int frameTypeAck = 0x03;

  final int frameType;
  final Uint8List payload;

  BluetoothFrame({required this.frameType, required this.payload});

  /// Serialize this frame to wire bytes.
  Uint8List toBytes() {
    final payload = this.payload;
    final length = 6 + payload.length + 2; // header + payload + checksum
    final bytes = Uint8List(length);

    bytes[0] = magic1;
    bytes[1] = magic2;
    bytes[2] = version;
    bytes[3] = frameType;
    bytes[4] = (payload.length >> 8) & 0xFF;
    bytes[5] = payload.length & 0xFF;
    bytes.setRange(6, 6 + payload.length, payload);

    int checksum = 0;
    for (var i = 0; i < 6 + payload.length; i++) {
      checksum += bytes[i];
    }
    bytes[6 + payload.length] = (checksum >> 8) & 0xFF;
    bytes[7 + payload.length] = checksum & 0xFF;

    return bytes;
  }

  /// Parse wire bytes into a frame. Returns null on malformed input.
  static BluetoothFrame? fromBytes(Uint8List data) {
    if (data.length < 8) return null;
    if (data[0] != magic1 || data[1] != magic2 || data[2] != version) return null;

    final payloadLength = ((data[4] << 8) | data[5]);
    if (data.length < 6 + payloadLength + 2) return null;

    int expectedChecksum = 0;
    for (var i = 0; i < 6 + payloadLength; i++) {
      expectedChecksum += data[i];
    }
    final actualChecksum = ((data[6 + payloadLength] << 8) | data[7 + payloadLength]);
    if (expectedChecksum != actualChecksum) return null;

    final payload = Uint8List.fromList(data.sublist(6, 6 + payloadLength));
    return BluetoothFrame(frameType: data[3], payload: payload);
  }

  /// Build a chat-message frame payload as JSON bytes (no wrapper — Kotlin
  /// applies its own 2-byte length prefix when sending over the socket).
  static Uint8List chatPayload({
    required String fromPeerId,
    required String fromPeerName,
    required String toPeerId,
    required String content,
    required String clientMessageId,
    required DateTime sentAt,
  }) {
    final obj = {
      'type': 'chat',
      'fromPeerId': fromPeerId,
      'fromPeerName': fromPeerName,
      'toPeerId': toPeerId,
      'content': content,
      'clientMessageId': clientMessageId,
      'sentAt': sentAt.toUtc().toIso8601String(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(obj)));
  }

  /// Parse a chat-message frame payload.
  static BluetoothChatPayload? parseChatPayload(Uint8List payload) {
    try {
      final decoded = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      return BluetoothChatPayload(
        type: decoded['type']?.toString() ?? 'chat',
        fromPeerId: decoded['fromPeerId']?.toString() ?? '',
        fromPeerName: decoded['fromPeerName']?.toString() ?? '',
        toPeerId: decoded['toPeerId']?.toString() ?? '',
        content: decoded['content']?.toString() ?? '',
        clientMessageId: decoded['clientMessageId']?.toString() ?? '',
        sentAt: decoded['sentAt']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Deserialized chat payload carried inside a BluetoothFrame.
class BluetoothChatPayload {
  final String type;
  final String fromPeerId;
  final String fromPeerName;
  final String toPeerId;
  final String content;
  final String clientMessageId;
  final String sentAt;

  BluetoothChatPayload({
    required this.type,
    required this.fromPeerId,
    required this.fromPeerName,
    required this.toPeerId,
    required this.content,
    required this.clientMessageId,
    required this.sentAt,
  });
}
