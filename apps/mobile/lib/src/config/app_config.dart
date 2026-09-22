enum AppEnvironment { development, production }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.mapsEnabled = false,
    this.navigationEnabled = false,
    this.voiceIntercomEnabled = false,
    this.mapStyleUrl,
  });

  final AppEnvironment environment;
  final Uri? apiBaseUrl;
  final bool mapsEnabled;
  final bool navigationEnabled;
  final bool voiceIntercomEnabled;

  /// Client map style configuration, never a backend provider credential.
  final String? mapStyleUrl;

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
    const bool navigationEnabled = bool.fromEnvironment(
      'COMMRIDE_NAVIGATION_ENABLED',
      defaultValue: false,
    );
    const bool voiceIntercomEnabled = bool.fromEnvironment(
      'COMMRIDE_VOICE_INTERCOM_ENABLED',
      defaultValue: false,
    );
    const String rawMapStyleUrl = String.fromEnvironment(
      'COMMRIDE_MAP_STYLE_URL',
    );

    final AppEnvironment environment = switch (rawEnvironment) {
      'production' => AppEnvironment.production,
      _ => AppEnvironment.development,
    };

    return AppConfig(
      environment: environment,
      apiBaseUrl: rawApiBaseUrl.isEmpty ? null : Uri.tryParse(rawApiBaseUrl),
      mapsEnabled: mapsEnabled,
      navigationEnabled: navigationEnabled,
      voiceIntercomEnabled: voiceIntercomEnabled,
      mapStyleUrl: validateMapStyleUrl(rawMapStyleUrl),
    );
  }

  /// Reject insecure URLs and arbitrary style hosts in the pilot build.
  /// Never include a rejected URL in an error message: it may contain a key.
  static String? validateMapStyleUrl(String? value) {
    final Uri? uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'maps.geoapify.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !RegExp(r'^/v1/styles/[a-z0-9-]+/style\.json$').hasMatch(uri.path) ||
        (uri.queryParameters['apiKey']?.trim().isEmpty ?? true)) {
      return null;
    }
    return uri.toString();
  }
}
