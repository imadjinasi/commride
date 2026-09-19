enum AppEnvironment { development, production }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.mapsEnabled = false,
  });

  final AppEnvironment environment;
  final Uri? apiBaseUrl;
  final bool mapsEnabled;

  factory AppConfig.fromEnvironment() {
    const String rawEnvironment = String.fromEnvironment(
      'COMMRIDE_ENV',
      defaultValue: 'development',
    );
    const String rawApiBaseUrl = String.fromEnvironment(
      'COMMRIDE_API_BASE_URL',
    );
    const bool mapsEnabled = bool.fromEnvironment(
      'COMMRIDE_MAPS_ENABLED',
      defaultValue: false,
    );

    final AppEnvironment environment = switch (rawEnvironment) {
      'production' => AppEnvironment.production,
      _ => AppEnvironment.development,
    };

    return AppConfig(
      environment: environment,
      apiBaseUrl: rawApiBaseUrl.isEmpty ? null : Uri.tryParse(rawApiBaseUrl),
      mapsEnabled: mapsEnabled,
    );
  }
}
