class MessageDto {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String? receiverId;
  final String? communityId;
  final String? channelId;
  final String type;
  final String content;
  final String? mediaUrl;
  final int? fileSize;
  final String? fileName;
  final String status;
  final String? replyToId;
  final DateTime sentAt;
  final DateTime? editedAt;

  MessageDto({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    this.receiverId,
    this.communityId,
    this.channelId,
    this.type = 'Text',
    required this.content,
    this.mediaUrl,
    this.fileSize,
    this.fileName,
    this.status = 'Sent',
    this.replyToId,
    required this.sentAt,
    this.editedAt,
  });

  factory MessageDto.fromJson(Map<String, dynamic> json) => MessageDto(
        id: json['id']?.toString() ?? '',
        senderId: json['senderId']?.toString() ?? '',
        senderName: json['senderName'] ?? '',
        senderAvatar: json['senderAvatar'],
        receiverId: json['receiverId']?.toString(),
        communityId: json['communityId']?.toString(),
        channelId: json['channelId']?.toString(),
        type: _typeToString(json['type']),
        content: json['content'] ?? '',
        mediaUrl: json['mediaUrl'],
        fileSize: json['fileSize'],
        fileName: json['fileName'],
        status: _statusToString(json['status']),
        replyToId: json['replyToId']?.toString(),
        sentAt: DateTime.tryParse(json['sentAt'] ?? '') ?? DateTime.now(),
        editedAt: json['editedAt'] != null
            ? DateTime.tryParse(json['editedAt'])
            : null,
      );

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  // MessageType enum from C#: 0=Text,1=Image,2=File,3=Voice,4=System,5=Call,6=Location,7=Sticker
  static String _typeToString(dynamic v) {
    if (v is String) return v;
    switch (_toInt(v)) {
      case 1:
        return 'Image';
      case 2:
        return 'File';
      case 3:
        return 'Voice';
      case 4:
        return 'System';
      case 5:
        return 'Call';
      case 6:
        return 'Location';
      case 7:
        return 'Sticker';
      default:
        return 'Text';
    }
  }

  // MessageStatus enum from C#: 0=Sending,1=Sent,2=Delivered,3=Read,4=Failed,5=Edited,6=Deleted
  static String _statusToString(dynamic v) {
    if (v is String) return v;
    switch (_toInt(v)) {
      case 0:
        return 'Sending';
      case 2:
        return 'Delivered';
      case 3:
        return 'Read';
      case 4:
        return 'Failed';
      case 5:
        return 'Edited';
      case 6:
        return 'Deleted';
      default:
        return 'Sent';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'senderAvatar': senderAvatar,
        'receiverId': receiverId,
        'communityId': communityId,
        'channelId': channelId,
        'type': type,
        'content': content,
        'mediaUrl': mediaUrl,
        'fileSize': fileSize,
        'fileName': fileName,
        'status': status,
        'replyToId': replyToId,
        'sentAt': sentAt.toIso8601String(),
        'editedAt': editedAt?.toIso8601String(),
      };
}

class SendMessageRequest {
  final String? receiverId;
  final String? communityId;
  final String? channelId;
  final String type;
  final String content;
  final String? mediaUrl;
  final int? fileSize;
  final String? fileName;
  final String? replyToId;
  final String clientMessageId;

  SendMessageRequest({
    this.receiverId,
    this.communityId,
    this.channelId,
    this.type = 'Text',
    required this.content,
    this.mediaUrl,
    this.fileSize,
    this.fileName,
    this.replyToId,
    String? clientMessageId,
  }) : clientMessageId = clientMessageId ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'receiverId': receiverId,
        'communityId': communityId,
        'channelId': channelId,
        'type': type,
        'content': content,
        'mediaUrl': mediaUrl,
        'fileSize': fileSize,
        'fileName': fileName,
        'replyToId': replyToId,
        'clientMessageId': clientMessageId,
      };
}
