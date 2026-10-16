class CommunityDto {
  final String id;
  final String name;
  final String? description;
  final String? iconUrl;
  final String ownerId;
  final String ownerName;
  final bool isPublic;
  final int memberCount;
  final DateTime createdAt;

  CommunityDto({
    required this.id,
    required this.name,
    this.description,
    this.iconUrl,
    required this.ownerId,
    required this.ownerName,
    this.isPublic = true,
    this.memberCount = 1,
    required this.createdAt,
  });

  factory CommunityDto.fromJson(Map<String, dynamic> json) => CommunityDto(
        id: json['id']?.toString() ?? '',
        name: json['name'] ?? '',
        description: json['description'],
        iconUrl: json['iconUrl'],
        ownerId: json['ownerId']?.toString() ?? '',
        ownerName: json['ownerName'] ?? '',
        isPublic: json['isPublic'] ?? true,
        memberCount: json['memberCount'] ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class ChannelDto {
  final String id;
  final String communityId;
  final String name;
  final String? description;
  final bool isVoice;
  final int sortOrder;

  ChannelDto({
    required this.id,
    required this.communityId,
    required this.name,
    this.description,
    this.isVoice = false,
    this.sortOrder = 0,
  });

  factory ChannelDto.fromJson(Map<String, dynamic> json) => ChannelDto(
        id: json['id']?.toString() ?? '',
        communityId: json['communityId']?.toString() ?? '',
        name: json['name'] ?? '',
        description: json['description'],
        isVoice: json['isVoice'] ?? false,
        sortOrder: json['sortOrder'] ?? 0,
      );
}
