class AppConfig {
  const AppConfig({
    required this.adminApiBaseUrl,
    required this.appApiBaseUrl,
    required this.imSocketUrl,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      adminApiBaseUrl: String.fromEnvironment(
        'ADMIN_API_BASE_URL',
        defaultValue: 'https://microblueplanet.com/beep-admin',
      ),
      appApiBaseUrl: String.fromEnvironment(
        'APP_API_BASE_URL',
        defaultValue: 'https://microblueplanet.com/beep-user',
      ),
      imSocketUrl: String.fromEnvironment(
        'IM_SOCKET_URL',
        defaultValue: 'https://microblueplanet.com',
      ),
    );
  }

  final String adminApiBaseUrl;
  final String appApiBaseUrl;
  final String imSocketUrl;
}

const appConfig = AppConfig(
  adminApiBaseUrl: String.fromEnvironment(
    'ADMIN_API_BASE_URL',
    defaultValue: 'https://microblueplanet.com/beep-admin',
  ),
  appApiBaseUrl: String.fromEnvironment(
    'APP_API_BASE_URL',
    defaultValue: 'https://microblueplanet.com/beep-user',
  ),
  imSocketUrl: String.fromEnvironment(
    'IM_SOCKET_URL',
    defaultValue: 'https://microblueplanet.com',
  ),
);
