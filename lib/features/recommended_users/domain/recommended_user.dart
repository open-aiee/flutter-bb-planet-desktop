class RecommendedUser {
  const RecommendedUser({
    required this.id,
    required this.nickName,
    required this.nameAlias,
    required this.avatarUrl,
    required this.onlineStatus,
    required this.fans,
    required this.followStatus,
    this.lastLoginTime,
  });

  final int id;
  final String nickName;
  final String nameAlias;
  final String avatarUrl;
  final int onlineStatus;
  final int fans;
  final int followStatus;
  final DateTime? lastLoginTime;

  bool get isOnline => onlineStatus == 1;

  String get displayName {
    final alias = nameAlias.trim();
    if (alias.isNotEmpty) {
      return alias;
    }
    final nickname = nickName.trim();
    if (nickname.isNotEmpty) {
      return nickname;
    }
    return 'User $id';
  }

  factory RecommendedUser.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    return RecommendedUser(
      id: _firstNonZeroInt([
        user['id'],
        user['userId'],
        user['uid'],
        json['userId'],
        json['uid'],
        json['fromUserId'],
        json['id'],
      ]),
      nickName: _firstNonEmptyString([
        json['nickName'],
        json['nickname'],
        user['nickName'],
        user['nickname'],
        user['name'],
      ]),
      nameAlias: _firstNonEmptyString([
        json['nameAlias'],
        user['nameAlias'],
        user['alias'],
      ]),
      avatarUrl: _firstNonEmptyString([
        json['avatarUrl'],
        json['avatar'],
        user['avatarUrl'],
        user['avatar'],
      ]),
      onlineStatus: _firstNonZeroInt([
        _onlineDataValue(json['onlineData']),
        _onlineDataValue(user['onlineData']),
        json['onlineStatus'],
        json['online'],
        json['isOnline'],
        json['userOnlineStatus'],
        json['status'],
        user['onlineStatus'],
        user['online'],
        user['isOnline'],
        user['userOnlineStatus'],
        user['status'],
      ]),
      fans: _firstNonZeroInt([json['fans'], user['fans']]),
      followStatus: _firstNonZeroInt([
        json['followStatus'],
        json['fs'],
        user['followStatus'],
        user['fs'],
      ]),
      lastLoginTime: _asDateTime(
        json['lastLoginTime'] ?? user['lastLoginTime'],
      ),
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static Object? _onlineDataValue(Object? value) {
    final data = _asMap(value);
    if (data.isEmpty) {
      return null;
    }
    return data['online'];
  }

  static int _firstNonZeroInt(List<Object?> values) {
    for (final value in values) {
      final parsed = _asInt(value);
      if (parsed != 0) {
        return parsed;
      }
    }
    return 0;
  }

  static String _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      final parsed = value?.toString().trim() ?? '';
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }
    return '';
  }

  static int _asInt(Object? value) {
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _asDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      final milliseconds = value > 100000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return DateTime.tryParse(value.toString());
  }
}
