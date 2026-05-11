class OperatorSession {
  const OperatorSession({
    required this.id,
    required this.userName,
    required this.displayName,
    required this.certificate,
    required this.source,
    this.roleId,
    this.bindGoogleData,
  });

  final int id;
  final String userName;
  final String displayName;
  final String certificate;
  final String source;
  final int? roleId;
  final String? bindGoogleData;

  bool get needsGoogleBinding =>
      bindGoogleData != null && bindGoogleData!.isNotEmpty;

  factory OperatorSession.fromLoginResponse({
    required Map<String, dynamic> data,
    required String certificate,
  }) {
    final idValue = data['id'];
    final roleIdValue = data['roleId'];
    final userName = data['userName']?.toString() ?? '';
    final nickName = data['nickName']?.toString();
    final realName = data['realName']?.toString();

    return OperatorSession(
      id: idValue is int
          ? idValue
          : int.tryParse(idValue?.toString() ?? '') ?? 0,
      userName: userName,
      displayName: _firstNotBlank([nickName, realName, userName, 'Operator']),
      certificate: certificate,
      source: data['source']?.toString() ?? 'admin',
      roleId: roleIdValue is int
          ? roleIdValue
          : int.tryParse(roleIdValue?.toString() ?? ''),
      bindGoogleData: data['bingGoogleData']?.toString(),
    );
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
