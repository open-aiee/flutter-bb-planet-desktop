class LocalChatPeerProfile {
  const LocalChatPeerProfile({
    required this.appUserId,
    required this.peerUserId,
    required this.displayName,
    required this.avatarUrl,
    required this.updatedAt,
  });

  final int appUserId;
  final int peerUserId;
  final String displayName;
  final String avatarUrl;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'appUserId': appUserId,
      'peerUserId': peerUserId,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory LocalChatPeerProfile.fromJson(Map<String, dynamic> json) {
    return LocalChatPeerProfile(
      appUserId: _asInt(json['appUserId']),
      peerUserId: _asInt(json['peerUserId']),
      displayName: json['displayName']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      updatedAt: _asDateTime(json['updatedAt']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _asDateTime(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }
}
