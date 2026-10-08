/// Runtime backend selection.
///
/// Firebase remains the default. A NAS deployment can be selected without
/// changing Dart code:
///
/// flutter run --dart-define=WORDCALENDAR_BACKEND=nas \
///   --dart-define=WORDCALENDAR_NAS_BASE_URL=https://nas.example.com
class BackendConfig {
  const BackendConfig._();

  static const String backendName = String.fromEnvironment(
    'WORDCALENDAR_BACKEND',
    defaultValue: 'firebase',
  );
  static const String nasBaseUrl = String.fromEnvironment(
    'WORDCALENDAR_NAS_BASE_URL',
    defaultValue: '',
  );
  static const String nasToken = String.fromEnvironment(
    'WORDCALENDAR_NAS_TOKEN',
    defaultValue: '',
  );

  static bool get useNas => backendName.toLowerCase() == 'nas';

  static Uri get nasBaseUri {
    final value = nasBaseUrl.trim();
    if (value.isEmpty) {
      throw StateError(
        'NAS 모드에는 WORDCALENDAR_NAS_BASE_URL이 필요합니다.',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('WORDCALENDAR_NAS_BASE_URL은 올바른 HTTP/HTTPS URL이어야 합니다.');
    }
    return uri;
  }
}
