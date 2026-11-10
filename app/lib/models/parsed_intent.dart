import 'recurrence.dart';
import 'reminder.dart';

/// Result of the deterministic on-device parser (CLAUDE.md §9).
///
/// The [outcome] is decided by a structural gate (not a confidence float):
/// - [resolved]    : safe to use locally — no LLM call.
/// - [clarify]     : a template almost matched; ask ONE local question.
/// - [unparseable] : fall back to Gemini (`/v1/parse`).
enum ParseOutcome { resolved, clarify, unparseable }

class ParsedIntent {
  const ParsedIntent({
    required this.outcome,
    required this.rawText,
    this.task,
    this.locationText,
    this.locationType,
    this.remindAt,
    this.recurrence = Recurrence.none,
    this.clarifyPrompt,
  });

  final ParseOutcome outcome;
  final String rawText;

  final String? task;
  final String? locationText;
  final LocationType? locationType;

  /// Recognised fire time, if any. From Phase 8 this is an actual trigger
  /// (time-based scheduling), not just a parse safeguard.
  final DateTime? remindAt;

  /// Recognised recurrence, if any (Phase 8).
  final Recurrence recurrence;

  /// Set when [outcome] is [clarify].
  final String? clarifyPrompt;

  bool get hasTask => task != null && task!.trim().isNotEmpty;
  bool get hasLocation => locationText != null && locationText!.trim().isNotEmpty;
  bool get hasTime => remindAt != null;

  factory ParsedIntent.unparseable(String raw) =>
      ParsedIntent(outcome: ParseOutcome.unparseable, rawText: raw);

  factory ParsedIntent.clarify(String raw, String prompt,
          {String? task,
          String? locationText,
          LocationType? locationType,
          DateTime? remindAt,
          Recurrence recurrence = Recurrence.none}) =>
      ParsedIntent(
        outcome: ParseOutcome.clarify,
        rawText: raw,
        clarifyPrompt: prompt,
        task: task,
        locationText: locationText,
        locationType: locationType,
        remindAt: remindAt,
        recurrence: recurrence,
      );
}
