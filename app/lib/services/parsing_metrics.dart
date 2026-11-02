import 'package:flutter/foundation.dart';

/// Minimal in-memory observability for the hybrid parser (CLAUDE.md §9).
///
/// No new infrastructure: just counters we can read in a debug view or log.
/// Backend LLM latency/tokens/cost are captured server-side separately.
class ParsingMetrics {
  int localResolved = 0;
  int localClarify = 0;
  int llmFallback = 0;
  int errors = 0;

  int get total => localResolved + localClarify + llmFallback + errors;

  /// Share of requests that needed the LLM (0..1).
  double get fallbackRate => total == 0 ? 0 : llmFallback / total;

  /// Share handled entirely on-device (resolved or clarified).
  double get localHandledRate =>
      total == 0 ? 0 : (localResolved + localClarify) / total;

  void recordLocalResolved() {
    localResolved++;
    _log();
  }

  void recordClarify() {
    localClarify++;
    _log();
  }

  void recordFallback() {
    llmFallback++;
    _log();
  }

  void recordError() {
    errors++;
    _log();
  }

  Map<String, num> snapshot() => {
        'localResolved': localResolved,
        'localClarify': localClarify,
        'llmFallback': llmFallback,
        'errors': errors,
        'fallbackRate': double.parse(fallbackRate.toStringAsFixed(3)),
      };

  void _log() {
    if (kDebugMode) debugPrint('[parsing] ${snapshot()}');
  }
}
