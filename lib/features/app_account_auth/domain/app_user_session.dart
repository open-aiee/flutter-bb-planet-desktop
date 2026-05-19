class AppUserSession {
  const AppUserSession({
    required this.id,
    required this.email,
    required this.displayName,
    required this.certificate,
    required this.platform,
    required this.deviceId,
    this.avatarUrl,
    this.safePasswordStatus,
    this.googleCodeStatus,
  });

  final int id;
  final String email;
  final String displayName;
  final String certificate;
  final String platform;
  final String deviceId;
  final String? avatarUrl;
  final int? safePasswordStatus;
  final int? googleCodeStatus;

  AppUserSession copyWith({
    int? id,
    String? email,
    String? displayName,
    String? certificate,
    String? platform,
    String? deviceId,
    String? avatarUrl,
    int? safePasswordStatus,
    int? googleCodeStatus,
  }) {
    return AppUserSession(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      certificate: certificate ?? this.certificate,
      platform: platform ?? this.platform,
      deviceId: deviceId ?? this.deviceId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      safePasswordStatus: safePasswordStatus ?? this.safePasswordStatus,
      googleCodeStatus: googleCodeStatus ?? this.googleCodeStatus,
    );
  }

  factory AppUserSession.fromLoginResponse({
    required Map<String, dynamic> data,
    required String certificate,
  }) {
    final idValue = data['id'];
    final nickName = data['nickName']?.toString();
    final nameAlias = data['nameAlias']?.toString();
    final email = data['email']?.toString() ?? '';

    return AppUserSession(
      id: idValue is int
          ? idValue
          : int.tryParse(idValue?.toString() ?? '') ?? 0,
      email: email,
      displayName: _firstNotBlank([nickName, nameAlias, email, 'APP Account']),
      certificate: certificate,
      platform: data['platform']?.toString() ?? 'PC',
      deviceId: data['deviceId']?.toString() ?? '',
      avatarUrl: data['avatarUrl']?.toString(),
      safePasswordStatus: _asInt(data['safePasswordStatus']),
      googleCodeStatus: _asInt(data['googleCodeStatus']),
    );
  }

  static int? _asInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  static String _firstNotBlank(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }
}
