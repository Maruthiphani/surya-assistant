import '../models/parsed_intent.dart';
import '../models/reminder.dart';
import '../parsing/intent_parser.dart';
import '../parsing/time_grammar.dart';
import '../utils/lru_cache.dart';
import 'ai_service.dart';
import 'parsing_metrics.dart';

/// Outcome of composing a reminder from a transcript.
sealed class ComposeResult {
  const ComposeResult();
}

/// A reminder draft ready for the confirmation screen. Coordinates for a
/// `specific` reminder are resolved at save time (Places), not here.
class ComposeResolved extends ComposeResult {
  const ComposeResolved(this.draft, {required this.fromFallback});
  final Reminder draft;
  final bool fromFallback; // true → came from the LLM
}

/// One on-device question is needed before we can build the reminder. The
/// [partialDraft] prefills the review screen with whatever was understood; the
/// missing slot is blank for the user to complete.
class ComposeClarify extends ComposeResult {
  const ComposeClarify(this.prompt, this.partialDraft);
  final String prompt;
  final Reminder partialDraft;
}

/// Couldn't compose (e.g. LLM unreachable offline on an unparseable command).
class ComposeFailed extends ComposeResult {
  const ComposeFailed(this.message);
  final String message;
}

/// Local-first reminder composition (CLAUDE.md §9).
///
/// Tries the on-device [IntentParser] first; only calls Gemini (via
/// [AiService]) on UNPARSEABLE, with an LRU cache keyed on the transcript with
/// relative-time tokens stripped (so "tomorrow" is never cached). Records
/// metrics for observability.
class ReminderComposer {
  ReminderComposer({
    required AiService aiService,
    required ParsingMetrics metrics,
    IntentParser parser = const IntentParser(),
    LruCache<String, ParseResult>? llmCache,
  })  : _ai = aiService,
        _metrics = metrics,
        _parser = parser,
        _llmCache = llmCache ?? LruCache(maxSize: 50);

  final AiService _ai;
  final ParsingMetrics _metrics;
  final IntentParser _parser;
  final LruCache<String, ParseResult> _llmCache;

  Future<ComposeResult> compose(String transcript, {double? lat, double? lng}) async {
    final intent = _parser.parse(transcript);

    switch (intent.outcome) {
      case ParseOutcome.resolved:
        _metrics.recordLocalResolved();
        return ComposeResolved(_draftFromIntent(intent), fromFallback: false);

      case ParseOutcome.clarify:
        _metrics.recordClarify();
        return ComposeClarify(intent.clarifyPrompt!, _partialDraft(intent));

      case ParseOutcome.unparseable:
        return _fallback(transcript, lat: lat, lng: lng);
    }
  }

  Future<ComposeResult> _fallback(String transcript, {double? lat, double? lng}) async {
    final key = _cacheKey(transcript);
    try {
      var result = _llmCache.get(key);
      if (result == null) {
        result = await _ai.parse(transcript, lat: lat, lng: lng);
        _llmCache.put(key, result);
      }
      _metrics.recordFallback();
      return ComposeResolved(_draftFromParse(result), fromFallback: true);
    } catch (_) {
      _metrics.recordError();
      return const ComposeFailed(
        "I couldn't understand that — please try rephrasing, "
        "e.g. \"remind me to buy milk at Walmart\".",
      );
    }
  }

  /// Cache key: normalized transcript with any time expression removed, so two
  /// requests that differ only by relative time don't collide or get stale.
  String _cacheKey(String transcript) {
    final norm = transcript.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    return TimeGrammar.extract(norm, DateTime.now()).cleanedText;
  }

  /// A prefill draft from a partial (clarify) parse — blanks for missing slots.
  Reminder _partialDraft(ParsedIntent i) {
    final type = i.locationType ?? LocationType.query;
    return Reminder(
      task: i.task ?? '',
      locationName: i.locationText ?? '',
      locationType: type,
      locationQuery: type == LocationType.query ? i.locationText : null,
      remindAt: i.remindAt,
      recurrence: i.recurrence,
      status: ReminderStatus.active,
    );
  }

  Reminder _draftFromIntent(ParsedIntent i) {
    // Time-only reminder (e.g. a birthday) has no location text.
    final hasLoc = i.locationText != null && i.locationText!.trim().isNotEmpty;
    final type = i.locationType ?? LocationType.query;
    final isQuery = type == LocationType.query;
    return Reminder(
      task: i.task!,
      locationName: hasLoc ? i.locationText! : '',
      locationType: type,
      locationQuery: (hasLoc && isQuery) ? i.locationText : null,
      remindAt: i.remindAt,
      recurrence: i.recurrence,
      status: ReminderStatus.active,
    );
  }

  Reminder _draftFromParse(ParseResult p) {
    final isQuery = p.locationType == LocationType.query;
    return Reminder(
      task: p.task,
      locationName: p.locationName,
      locationType: p.locationType,
      locationQuery: isQuery ? (p.locationQuery ?? p.locationName) : null,
      // The backend may return one specific candidate; coords are finalised at
      // save time (picker if >1), so we don't set lat/lng on the draft here.
      status: ReminderStatus.active,
    );
  }
}
