class UserDto {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String status;
  final int role;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  UserDto({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.status = 'Online',
    this.role = 0,
    this.lastSeenAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
        id: json['id']?.toString() ?? '',
        username: json['username'] ?? '',
        displayName: json['displayName'] ?? json['username'] ?? '',
        avatarUrl: json['avatarUrl'],
        bio: json['bio'],
        status: _statusToString(json['status']),
        role: _toInt(json['role']),
        lastSeenAt: json['lastSeenAt'] != null
            ? DateTime.tryParse(json['lastSeenAt'])
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
            : DateTime.now(),
      );

  bool get isAdmin => role >= 2;

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  // ConnectionStatus enum from C#: 0=Offline,1=Online,2=Away,3=Busy,4=DND,5=Invisible
  static String _statusToString(dynamic v) {
    if (v is String) return v;
    final n = _toInt(v);
    switch (n) {
      case 0:
        return 'Offline';
      case 1:
        return 'Online';
      case 2:
        return 'Away';
      case 3:
        return 'Busy';
      case 4:
        return 'DoNotDisturb';
      case 5:
        return 'Invisible';
      default:
        return 'Offline';
    }
  }
}

class AuthResponse {
  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final UserDto user;

  AuthResponse({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        token: json['token'] ?? '',
        refreshToken: json['refreshToken'] ?? '',
        expiresAt: DateTime.tryParse(json['expiresAt'] ?? '') ?? DateTime.now(),
        user: UserDto.fromJson(json['user'] ?? {}),
      );
}
