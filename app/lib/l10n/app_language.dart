/// The languages Hanu supports (CLAUDE.md Phase 9 — Multilingual Hanu).
///
/// Drives three things: the on-device speech-recognition locale, the text-to-
/// speech voice, and which [AppStrings] the UI renders. User *content* (task
/// text, item names) is never machine-translated — only the app's own chrome
/// and spoken scaffolding are localized.
enum AppLanguage {
  english,
  hindi,
  telugu;

  /// Stored on the profile as a short code ("en"/"hi"/"te").
  String get code {
    switch (this) {
      case AppLanguage.english:
        return 'en';
      case AppLanguage.hindi:
        return 'hi';
      case AppLanguage.telugu:
        return 'te';
    }
  }

  /// Name shown in the language picker, in its own script.
  String get displayName {
    switch (this) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.hindi:
        return 'हिन्दी';
      case AppLanguage.telugu:
        return 'తెలుగు';
    }
  }

  /// BCP-47 locale for `speech_to_text` and `flutter_tts`. Mixed-language
  /// recognition (e.g. Hindi-English) is handled by the device engine when set
  /// to the hi/te locale — availability depends on installed language packs.
  String get localeId {
    switch (this) {
      case AppLanguage.english:
        return 'en-US';
      case AppLanguage.hindi:
        return 'hi-IN';
      case AppLanguage.telugu:
        return 'te-IN';
    }
  }

  static AppLanguage fromCode(String? code) {
    switch (code) {
      case 'hi':
        return AppLanguage.hindi;
      case 'te':
        return AppLanguage.telugu;
      case 'en':
      default:
        return AppLanguage.english;
    }
  }
}
