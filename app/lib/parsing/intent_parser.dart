import '../models/parsed_intent.dart';
import '../models/recurrence.dart';
import '../models/reminder.dart';
import 'date_grammar.dart';
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

    // 1) Extract + remove any time-of-day/relative expression, then any
    //    absolute date / recurrence phrase (Phase 8).
    final tm = TimeGrammar.extract(rest, clock);
    final dm = DateGrammar.extract(tm.cleanedText, clock);
    final recurrence = dm.recurrence;
    final remindAt = _combine(dm.date, tm.remindAt, recurrence, clock);
    final work = dm.cleanedText;

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
    final hasTime = remindAt != null;

    // A trigger is a location OR a time (Phase 8: time is now a real trigger).
    if (hasTask && (hasLoc || hasTime)) {
      return ParsedIntent(
        outcome: ParseOutcome.resolved,
        rawText: input,
        task: task,
        locationText: locationText,
        locationType: locType,
        remindAt: remindAt,
        recurrence: recurrence,
      );
    }
    if (hasLoc && !hasTask) {
      return ParsedIntent.clarify(
        input,
        'What should I remind you to do at ${_cap(locationText)}?',
        locationText: locationText,
        locationType: locType,
        remindAt: remindAt,
        recurrence: recurrence,
      );
    }
    // A recurrence/date with no time-of-day → ask for the time (Phase 8:
    // "ask for missing date or time").
    if (hasTask && recurrence.repeats && !hasTime) {
      return ParsedIntent.clarify(
        input,
        'What time should I remind you to $task?',
        task: task,
        recurrence: recurrence,
      );
    }
    if (hasTask && !hasLoc && !hasTime) {
      return ParsedIntent.clarify(
        input,
        'Where or when should I remind you to $task?',
        task: task,
        recurrence: recurrence,
      );
    }
    return ParsedIntent.unparseable(input);
  }

  /// Combine a date anchor (from DateGrammar) with a time-of-day (from
  /// TimeGrammar) into one fire time. Date wins the calendar day; time wins the
  /// clock. Date-only → default 9:00. A past one-shot date rolls to next year.
  DateTime? _combine(
      DateTime? date, DateTime? time, Recurrence recurrence, DateTime now) {
    if (date == null) return time; // time-only (or nothing)
    final hour = time?.hour ?? 9;
    final min = time?.minute ?? 0;
    var dt = DateTime(date.year, date.month, date.day, hour, min);
    if (!recurrence.repeats && dt.isBefore(now)) {
      dt = DateTime(date.year + 1, date.month, date.day, hour, min);
    }
    return dt;
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
