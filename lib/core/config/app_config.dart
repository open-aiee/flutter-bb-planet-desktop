class AppConfig {
  const AppConfig({
    required this.environment,
    required this.adminApiBaseUrl,
    required this.appApiBaseUrl,
    required this.imSocketUrl,
    required this.allowAuthBypass,
  });

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      environment: AppEnvironment.current,
      adminApiBaseUrl: AppEnvironment.adminApiBaseUrl,
      appApiBaseUrl: AppEnvironment.appApiBaseUrl,
      imSocketUrl: AppEnvironment.imSocketUrl,
      allowAuthBypass: AppEnvironment.allowAuthBypass,
    );
  }

  final String environment;
  final String adminApiBaseUrl;
  final String appApiBaseUrl;
  final String imSocketUrl;
  final bool allowAuthBypass;
}

class AppEnvironment {
  const AppEnvironment._();

  static const current = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'local',
  );
  static const _adminOverride = String.fromEnvironment('ADMIN_API_BASE_URL');
  static const _appOverride = String.fromEnvironment('APP_API_BASE_URL');
  static const _socketOverride = String.fromEnvironment('IM_SOCKET_URL');
  static const allowAuthBypass = bool.fromEnvironment(
    'ALLOW_AUTH_BYPASS',
    defaultValue: current == 'local',
  );

  static String get adminApiBaseUrl {
    if (_adminOverride.isNotEmpty) {
      return _trimTrailingSlash(_adminOverride);
    }
    return _trimTrailingSlash(switch (current) {
      'prod' => 'https://beepbeepplanet.com/beep-admin',
      'test' => 'https://microblueplanet.com/beep-admin',
      _ => 'http://192.168.0.101:31111',
    });
  }

  static String get appApiBaseUrl {
    if (_appOverride.isNotEmpty) {
      return _trimTrailingSlash(_appOverride);
    }
    return _trimTrailingSlash(switch (current) {
      'prod' => 'https://beepbeepplanet.com/beep-user',
      'test' => 'https://microblueplanet.com/beep-user',
      _ => 'http://192.168.0.101:31110',
    });
  }

  static String get imSocketUrl {
    if (_socketOverride.isNotEmpty) {
      return _trimTrailingSlash(_socketOverride);
    }
    return _trimTrailingSlash(switch (current) {
      'prod' => 'https://beepbeepplanet.com/common',
      'test' => 'https://microblueplanet.com/common',
      _ => 'http://192.168.0.101:5464/common',
    });
  }

  static String _trimTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}

final appConfig = AppConfig.fromEnvironment();
