import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// On-device speech-to-text (CLAUDE.md §2), behind an interface so the UI can be
/// tested with a fake and the engine swapped.
abstract class SpeechService {
  /// Initialise + request mic/speech permission. Returns whether STT is usable.
  Future<bool> init();

  bool get isAvailable;
  bool get isListening;

  /// Start listening; [onResult] fires with partial and final transcripts.
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  });

  Future<void> stop();
}

class SttSpeechService implements SpeechService {
  SttSpeechService({SpeechToText? stt}) : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  bool get isListening => _stt.isListening;

  @override
  Future<bool> init() async {
    _available = await _stt.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _available;
  }

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  }) async {
    if (!_available) {
      final ok = await init();
      if (!ok) return;
    }
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        onResult(r.recognizedWords, r.finalResult);
        if (r.finalResult) onDone?.call();
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}
