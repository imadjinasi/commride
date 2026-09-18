enum AppEnvironment {
  development,
  production,
}

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
  });

  final AppEnvironment environment;
  final Uri? apiBaseUrl;

  factory AppConfig.fromEnvironment() {
    const String rawEnvironment = String.fromEnvironment(
      'COMMRIDE_ENV',
      defaultValue: 'development',
    );
    const String rawApiBaseUrl = String.fromEnvironment('COMMRIDE_API_BASE_URL');

    final AppEnvironment environment = switch (rawEnvironment) {
      'production' => AppEnvironment.production,
      _ => AppEnvironment.development,
    };

    return AppConfig(
      environment: environment,
      apiBaseUrl: rawApiBaseUrl.isEmpty ? null : Uri.tryParse(rawApiBaseUrl),
    );
  }
}
