import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../l10n/app_language.dart';

/// Text-to-speech so Hanu can speak back in the user's language (CLAUDE.md
/// Phase 9). On-device/free. Behind an interface (§5) so it can be faked in
/// tests and no-op where TTS isn't available.
abstract class TtsService {
  Future<void> init();

  /// Speak [text] in [language]'s voice. Best-effort — silently no-ops if the
  /// device has no voice for that locale.
  Future<void> speak(String text, AppLanguage language);

  Future<void> stop();
}

class FlutterTtsService implements TtsService {
  FlutterTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
    } catch (e) {
      debugPrint('TTS init failed: $e');
    }
  }

  @override
  Future<void> speak(String text, AppLanguage language) async {
    if (text.trim().isEmpty) return;
    await init();
    try {
      // Set the language if the device has a voice for it; if not, speak in
      // whatever the default is rather than failing.
      final available = await _tts.isLanguageAvailable(language.localeId);
      if (available == true) {
        await _tts.setLanguage(language.localeId);
      }
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
