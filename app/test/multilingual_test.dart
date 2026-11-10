import 'package:flutter_test/flutter_test.dart';
import 'package:surya/l10n/app_language.dart';
import 'package:surya/l10n/app_strings.dart';

/// Phase 9 (Multilingual Hanu): the language model + localized strings are
/// pure, so they test directly.
void main() {
  group('AppLanguage', () {
    test('code round-trips, unknown/null → English (backward compatible)', () {
      for (final l in AppLanguage.values) {
        expect(AppLanguage.fromCode(l.code), l);
      }
      expect(AppLanguage.fromCode(null), AppLanguage.english);
      expect(AppLanguage.fromCode('fr'), AppLanguage.english);
    });

    test('locale ids map to the STT/TTS locales', () {
      expect(AppLanguage.english.localeId, 'en-US');
      expect(AppLanguage.hindi.localeId, 'hi-IN');
      expect(AppLanguage.telugu.localeId, 'te-IN');
    });

    test('display names are in their own script', () {
      expect(AppLanguage.hindi.displayName, 'हिन्दी');
      expect(AppLanguage.telugu.displayName, 'తెలుగు');
    });
  });

  group('AppStrings', () {
    test('every language provides every string (none blank)', () {
      for (final lang in AppLanguage.values) {
        final s = AppStrings.of(lang);
        final values = <String>[
          s.settingsTitle,
          s.assistantSection,
          s.assistantNameLabel,
          s.remindersSection,
          s.defaultRadiusLabel,
          s.languageSection,
          s.languageLabel,
          s.save,
          s.settingsSaved,
          s.speak,
          s.noRemindersTitle,
          s.noRemindersBody,
          s.voiceTitle,
          s.voicePrompt,
          s.voiceListening,
          s.voiceContinue,
          s.confirmReach('buy milk', 'Walmart'),
          s.confirmTime('call mom', 'Nov 7'),
          s.reminderTitle('Hanu'),
          s.nearBody('Costco', 'buy rice'),
        ];
        for (final v in values) {
          expect(v.trim(), isNotEmpty,
              reason: 'empty string for ${lang.code}');
        }
      }
    });

    test('user content is interpolated verbatim, not translated', () {
      final hi = AppStrings.of(AppLanguage.hindi);
      // The task/place passed in must appear unchanged in every language.
      expect(hi.confirmReach('buy milk', 'Walmart'), contains('buy milk'));
      expect(hi.confirmReach('buy milk', 'Walmart'), contains('Walmart'));
      final te = AppStrings.of(AppLanguage.telugu);
      expect(te.nearBody('Costco', 'buy rice'), contains('Costco'));
      expect(te.nearBody('Costco', 'buy rice'), contains('buy rice'));
    });

    test('languages actually differ (not all English)', () {
      expect(AppStrings.of(AppLanguage.hindi).save,
          isNot(AppStrings.of(AppLanguage.english).save));
      expect(AppStrings.of(AppLanguage.telugu).save,
          isNot(AppStrings.of(AppLanguage.english).save));
    });
  });
}
