class AppConstants {
  AppConstants._();

  static const appName = 'Fyleon';
  static const tagline = 'Open anything.';
  // Keep in sync with pubspec.yaml "version".
  static const version = '0.1.0';
  static const packageId = 'com.fyleon.app';

  // Phase 1 limits (protect memory on phones).
  static const maxTextBytes = 2 * 1024 * 1024;
  static const maxHighlightBytes = 300 * 1024;
  static const maxHighlightLines = 4000;
  static const maxArchiveBytes = 200 * 1024 * 1024;
  static const maxRecents = 200;
}
