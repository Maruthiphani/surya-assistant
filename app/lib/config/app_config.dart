/// App-wide configuration constants.
///
/// `apiBaseUrl` points at the Surya backend. For local development against a
/// backend running on the host machine, the Android emulator reaches the host
/// via 10.0.2.2 (not localhost). Override with --dart-define=API_BASE_URL=...
/// for a deployed Cloud Run URL.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8011',
  );

  // --- Billing (RevenueCat, Phase 6) ---------------------------------------

  /// Platform-specific RevenueCat public SDK keys, injected at build time, e.g.
  /// `--dart-define=RC_API_KEY_ANDROID=goog_xxx --dart-define=RC_API_KEY_IOS=appl_xxx`.
  /// When blank (dev default), billing is disabled and the app behaves as the
  /// Free tier — see SubscriptionService's graceful degradation.
  static const String revenueCatApiKeyAndroid =
      String.fromEnvironment('RC_API_KEY_ANDROID', defaultValue: '');
  static const String revenueCatApiKeyIos =
      String.fromEnvironment('RC_API_KEY_IOS', defaultValue: '');

  /// RevenueCat entitlement identifier that unlocks Pro.
  static const String proEntitlementId = 'pro';

  /// Free-tier cap on simultaneously active location reminders (CLAUDE.md §1).
  /// Pro is unlimited.
  static const int freeActiveReminderLimit = 5;
}
