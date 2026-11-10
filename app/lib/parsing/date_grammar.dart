/// Recognises absolute dates ("November 7", "7th Nov", "12/25") and recurrence
/// phrases ("every day", "weekly", "every Monday", "every year") in a command,
/// and strips them — the complement to TimeGrammar, which handles clock times
/// and relative days (CLAUDE.md Phase 8).
///
/// Returns a date-only anchor (midnight); the parser combines it with any
/// time-of-day from TimeGrammar (else a sensible default hour).
library;

import '../models/recurrence.dart';

class DateMatch {
  const DateMatch({
    this.date,
    this.recurrence = Recurrence.none,
    required this.cleanedText,
    required this.matched,
  });

  /// Absolute date anchor at midnight, if one was recognised.
  final DateTime? date;
  final Recurrence recurrence;
  final String cleanedText;
  final bool matched;

  static DateMatch none(String text) =>
      DateMatch(cleanedText: text, matched: false);
}

class DateGrammar {
  DateGrammar._();

  static const _months = {
    'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3,
    'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7,
    'august': 8, 'aug': 8, 'september': 9, 'sep': 9, 'sept': 9, 'october': 10,
    'oct': 10, 'november': 11, 'nov': 11, 'december': 12, 'dec': 12,
  };
  static const _weekdays = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7,
  };

  static final _monthAlt = _months.keys.join('|');
  static final _weekdayAlt = _weekdays.keys.join('|');

  static DateMatch extract(String text, DateTime now) {
    var t = text;
    var matched = false;
    var recurrence = Recurrence.none;
    int? weekday;
    DateTime? date;

    String strip(RegExpMatch m) {
      matched = true;
      return '${t.substring(0, m.start)} ${t.substring(m.end)}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    // --- Absolute date (do this before generic recurrence so "every Nov 7"
    //     becomes yearly-on-a-date, not a bare "every ...") ------------------

    // "november 7", "nov 7th", optionally preceded by "every" → yearly.
    final monthDay = RegExp(
        '\\b(every\\s+)?($_monthAlt)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b',
        caseSensitive: false);
    // "7 november", "7th of nov"
    final dayMonth = RegExp(
        '\\b(?:every\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?($_monthAlt)\\b',
        caseSensitive: false);
    // numeric M/D or M-D
    final numeric = RegExp(r'\b(\d{1,2})[/-](\d{1,2})\b');

    RegExpMatch? m;
    if ((m = monthDay.firstMatch(t)) != null) {
      final every = m!.group(1) != null;
      final month = _months[m.group(2)!.toLowerCase()]!;
      final day = int.parse(m.group(3)!);
      date = _resolveDate(month, day, now);
      if (every) recurrence = Recurrence.yearly;
      t = strip(m);
    } else if ((m = dayMonth.firstMatch(t)) != null) {
      final every = m![0]!.toLowerCase().contains('every');
      final day = int.parse(m.group(1)!);
      final month = _months[m.group(2)!.toLowerCase()]!;
      date = _resolveDate(month, day, now);
      if (every) recurrence = Recurrence.yearly;
      t = strip(m);
    } else if ((m = numeric.firstMatch(t)) != null) {
      final month = int.parse(m!.group(1)!);
      final day = int.parse(m.group(2)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        date = _resolveDate(month, day, now);
        t = strip(m);
      }
    }

    // --- Weekday recurrence: "every monday", "on mondays", "mondays" --------
    if (recurrence == Recurrence.none) {
      final everyWeekday = RegExp(
          '\\bevery\\s+($_weekdayAlt)\\b',
          caseSensitive: false);
      final pluralWeekday = RegExp(
          '\\b(?:on\\s+)?($_weekdayAlt)s\\b',
          caseSensitive: false);
      if ((m = everyWeekday.firstMatch(t)) != null) {
        weekday = _weekdays[m!.group(1)!.toLowerCase()];
        recurrence = Recurrence.weekly;
        t = strip(m);
      } else if ((m = pluralWeekday.firstMatch(t)) != null) {
        weekday = _weekdays[m!.group(1)!.toLowerCase()];
        recurrence = Recurrence.weekly;
        t = strip(m);
      }
    }

    // --- Generic recurrence words -------------------------------------------
    if (recurrence == Recurrence.none) {
      final patterns = <Recurrence, RegExp>{
        Recurrence.daily:
            RegExp(r'\b(every\s*day|everyday|daily|each\s+day)\b', caseSensitive: false),
        Recurrence.weekly:
            RegExp(r'\b(every\s+week|weekly)\b', caseSensitive: false),
        Recurrence.monthly:
            RegExp(r'\b(every\s+month|monthly)\b', caseSensitive: false),
        Recurrence.yearly:
            RegExp(r'\b(every\s+year|yearly|annually|each\s+year)\b',
                caseSensitive: false),
      };
      for (final entry in patterns.entries) {
        if ((m = entry.value.firstMatch(t)) != null) {
          recurrence = entry.key;
          t = strip(m!);
          break;
        }
      }
    }

    // A weekly-by-weekday reminder anchors to that weekday's next occurrence.
    if (date == null && weekday != null) {
      final days = (weekday - now.weekday) % 7;
      final base = DateTime(now.year, now.month, now.day);
      date = base.add(Duration(days: days));
    }

    if (!matched) return DateMatch.none(text);
    return DateMatch(
      date: date,
      recurrence: recurrence,
      cleanedText: _tidy(t),
      matched: true,
    );
  }

  /// A month/day with no year → the next upcoming occurrence (this year, or
  /// next year if the date has already passed). Midnight.
  static DateTime _resolveDate(int month, int day, DateTime now) {
    final lastDay = DateTime(now.year, month + 1, 0).day;
    final d = day <= lastDay ? day : lastDay;
    var candidate = DateTime(now.year, month, d);
    final today = DateTime(now.year, now.month, now.day);
    if (candidate.isBefore(today)) {
      candidate = DateTime(now.year + 1, month, d);
    }
    return candidate;
  }

  /// Drop a dangling connector ("on"/"at"/"by") left behind after removing the
  /// date, e.g. "wish mom happy birthday on" → "wish mom happy birthday".
  static String _tidy(String s) {
    return s
        .replaceAll(RegExp(r'\b(on|at|by)\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
