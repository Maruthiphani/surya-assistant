import '../models/parsed_intent.dart';
import '../models/reminder.dart';
import 'place_dictionaries.dart';
import 'time_grammar.dart';

/// Deterministic, on-device intent parser (CLAUDE.md §9).
///
/// Order matters: strip fillers → require a "remind me" anchor → pull out any
/// TIME first (so "5 PM" is never read as a place) → split off the LOCATION via
/// a connector → type the location against small dictionaries. The [outcome] is
/// decided by a structural gate, not a confidence float:
///   RESOLVED  = task + a location trigger, cleanly extracted.
///   CLARIFY   = template almost matched, exactly one slot missing.
///   UNPARSEABLE = no anchor / unknown place / multi-clause → LLM fallback.
class IntentParser {
  const IntentParser();

  // Location connectors, longest first so the longer phrase wins.
  static const _connectors = [
    "when i reach", "when i get to", "when i arrive at", "when i'm at",
    "when im at", "when i am at", "whenever i'm at", "whenever im at",
    "once i reach", "once i get to", " at ", " near ", " from ",
  ];

  ParsedIntent parse(String input, {DateTime? now}) {
    final clock = now ?? DateTime.now();

    var text = input
        .toLowerCase()
        .trim()
        .replaceFirst(RegExp(r'[.!?]+$'), '') // drop trailing sentence punctuation
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Strip leading fillers ("hey hanu,", "please", "can you").
    text = text.replaceFirst(
        RegExp(r"^(hey|hi|hello)\s+\S+[\s,]+", caseSensitive: false), '');
    text = text.replaceFirst(
        RegExp(r"^(ok|okay|please|can you|could you|would you|i want to|i'd like to)\s+",
            caseSensitive: false),
        '');

    // Anchor: must be a reminder command.
    final anchor = RegExp(r'^(remind me|set a reminder to|remind me to|remind)\b');
    if (!anchor.hasMatch(text)) return ParsedIntent.unparseable(input);
    var rest = text.replaceFirst(anchor, '').trim();
    rest = rest.replaceFirst(RegExp(r'^that\s+'), '');

    // Multi-instruction markers → let the LLM handle (keep "and" allowed in tasks).
    if (RegExp(r'\b(then|also|after that|plus)\b').hasMatch(rest)) {
      return ParsedIntent.unparseable(input);
    }

    // 1) Extract + remove any time expression.
    final tm = TimeGrammar.extract(rest, clock);
    final remindAt = tm.remindAt;
    final work = tm.cleanedText;

    // 2) Split on the earliest location connector.
    int connIdx = -1;
    var connector = '';
    for (final c in _connectors) {
      final i = work.indexOf(c);
      if (i >= 0 && (connIdx == -1 || i < connIdx)) {
        connIdx = i;
        connector = c;
      }
    }

    String taskPart;
    String? locPart;
    if (connIdx >= 0) {
      taskPart = work.substring(0, connIdx).trim();
      locPart = work.substring(connIdx + connector.length).trim();
    } else {
      taskPart = work.trim();
      locPart = null;
    }

    // A second connector inside the location means multiple places → LLM.
    if (locPart != null) {
      for (final c in _connectors) {
        if (locPart.contains(c)) return ParsedIntent.unparseable(input);
      }
    }

    var task = taskPart.replaceFirst(RegExp(r'^to\s+'), '').trim();

    // 3) Type the location.
    LocationType? locType;
    String? locationText;
    if (locPart != null && locPart.isNotEmpty) {
      final typing = PlaceDictionaries.typeLocation(locPart);
      if (typing.isUnknown) return ParsedIntent.unparseable(input);
      locType = typing.type;
      locationText = typing.normalized;
    }

    final hasTask = task.isNotEmpty;
    final hasLoc = locationText != null;

    if (hasTask && hasLoc) {
      return ParsedIntent(
        outcome: ParseOutcome.resolved,
        rawText: input,
        task: task,
        locationText: locationText,
        locationType: locType,
        remindAt: remindAt,
      );
    }
    if (hasLoc && !hasTask) {
      return ParsedIntent.clarify(
        input,
        'What should I remind you to do at ${_cap(locationText)}?',
        locationText: locationText,
        locationType: locType,
        remindAt: remindAt,
      );
    }
    if (hasTask && !hasLoc) {
      final suffix =
          remindAt != null ? ' (time-only reminders are coming soon)' : '';
      return ParsedIntent.clarify(
        input,
        'Where should I remind you to $task?$suffix',
        task: task,
        remindAt: remindAt,
      );
    }
    return ParsedIntent.unparseable(input);
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
