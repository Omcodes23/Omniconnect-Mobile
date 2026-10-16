class FriendRequestDto {
  final String id;
  final String requesterId;
  final String requesterName;
  final String? requesterAvatar;
  final String addresseeId;
  final String addresseeName;
  final String? addresseeAvatar;
  final bool isAccepted;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  FriendRequestDto({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    this.requesterAvatar,
    required this.addresseeId,
    required this.addresseeName,
    this.addresseeAvatar,
    this.isAccepted = false,
    required this.createdAt,
    this.acceptedAt,
  });

  factory FriendRequestDto.fromJson(Map<String, dynamic> json) =>
      FriendRequestDto(
        id: json['id']?.toString() ?? '',
        requesterId: json['requesterId']?.toString() ?? '',
        requesterName: json['requesterName'] ?? '',
        requesterAvatar: json['requesterAvatar'],
        addresseeId: json['addresseeId']?.toString() ?? '',
        addresseeName: json['addresseeName'] ?? '',
        addresseeAvatar: json['addresseeAvatar'],
        isAccepted: json['isAccepted'] ?? false,
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        acceptedAt: json['acceptedAt'] != null
            ? DateTime.tryParse(json['acceptedAt'])
            : null,
      );
}
