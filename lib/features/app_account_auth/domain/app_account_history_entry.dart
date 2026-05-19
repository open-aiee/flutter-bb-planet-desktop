class AppAccountHistoryEntry {
  const AppAccountHistoryEntry({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.password,
    required this.token,
    required this.updatedAt,
  });

  final int id;
  final String email;
  final String displayName;
  final String avatarUrl;
  final String password;
  final String token;
  final DateTime updatedAt;

  bool get canLogin => email.trim().isNotEmpty && password.isNotEmpty;

  AppAccountHistoryEntry copyWith({
    int? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    String? password,
    String? token,
    DateTime? updatedAt,
  }) {
    return AppAccountHistoryEntry(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      password: password ?? this.password,
      token: token ?? this.token,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'password': password,
      'token': token,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AppAccountHistoryEntry.fromJson(Map<String, dynamic> json) {
    return AppAccountHistoryEntry(
      id: _asInt(json['id']),
      email: json['email']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
