/// Lightweight time/date recognizer (CLAUDE.md §9).
///
/// Its job: find a time expression in the text, resolve a best-effort
/// [DateTime], and REMOVE that span (plus a leading "at/by/around/on") so the
/// rest of the parser never mistakes "5 PM" for a place. Resolution is
/// best-effort — time is recognised but not yet acted upon.
library;

class TimeMatch {
  const TimeMatch({required this.remindAt, required this.cleanedText, required this.matched});

  final DateTime? remindAt;
  final String cleanedText;
  final bool matched;

  static TimeMatch none(String text) =>
      TimeMatch(remindAt: null, cleanedText: text, matched: false);
}

class TimeGrammar {
  TimeGrammar._();

  // Default hours for vague parts of day.
  static const _partHour = {
    'morning': 8,
    'afternoon': 13,
    'evening': 18,
    'night': 20,
  };
  static const _weekdays = {
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7,
  };

  // Optional leading connector so "at 5 pm" / "by tomorrow" is removed whole.
  static const _lead = r'(?:\b(?:at|by|around|on)\s+)?';

  /// Try patterns (most specific first); return the earliest match.
  static TimeMatch extract(String text, DateTime now) {
    final candidates = <(RegExpMatch, DateTime?)>[];

    void tryPattern(RegExp re, DateTime? Function(RegExpMatch) resolve) {
      final m = re.firstMatch(text);
      if (m != null) candidates.add((m, resolve(m)));
    }

    // in N minutes/hours/days
    tryPattern(
      RegExp(r'\bin\s+(\d+)\s+(minutes?|mins?|hours?|hrs?|days?)\b',
          caseSensitive: false),
      (m) {
        final n = int.parse(m.group(1)!);
        final unit = m.group(2)!.toLowerCase();
        if (unit.startsWith('min')) return now.add(Duration(minutes: n));
        if (unit.startsWith('h')) return now.add(Duration(hours: n));
        return now.add(Duration(days: n));
      },
    );

    // today/tonight/tomorrow [morning|afternoon|evening|night]
    tryPattern(
      RegExp('$_lead' r'(today|tonight|tomorrow)(?:\s+(morning|afternoon|evening|night))?\b',
          caseSensitive: false),
      (m) {
        final day = m.group(1)!.toLowerCase();
        final part = m.group(2)?.toLowerCase();
        var date = DateTime(now.year, now.month, now.day);
        if (day == 'tomorrow') date = date.add(const Duration(days: 1));
        final hour = part != null ? _partHour[part]! : (day == 'tonight' ? 20 : 9);
        return DateTime(date.year, date.month, date.day, hour);
      },
    );

    // this morning/afternoon/evening
    tryPattern(
      RegExp(r'\bthis\s+(morning|afternoon|evening)\b', caseSensitive: false),
      (m) {
        final hour = _partHour[m.group(1)!.toLowerCase()]!;
        return DateTime(now.year, now.month, now.day, hour);
      },
    );

    // [next] weekday [part]
    tryPattern(
      RegExp('$_lead' r'(?:(next)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+(morning|afternoon|evening|night))?\b',
          caseSensitive: false),
      (m) {
        final target = _weekdays[m.group(2)!.toLowerCase()]!;
        var days = (target - now.weekday) % 7;
        if (days == 0 || m.group(1) != null) days += 7; // next occurrence
        final date = DateTime(now.year, now.month, now.day).add(Duration(days: days));
        final part = m.group(3)?.toLowerCase();
        final hour = part != null ? _partHour[part]! : 9;
        return DateTime(date.year, date.month, date.day, hour);
      },
    );

    // clock: 5 pm, 5:30 pm, 12 am
    tryPattern(
      RegExp('$_lead' r'(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?\b',
          caseSensitive: false),
      (m) {
        var h = int.parse(m.group(1)!);
        final min = m.group(2) != null ? int.parse(m.group(2)!) : 0;
        final pm = m.group(3)!.toLowerCase() == 'p';
        h = (h % 12) + (pm ? 12 : 0);
        var dt = DateTime(now.year, now.month, now.day, h, min);
        if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
        return dt;
      },
    );

    // 24h clock only when led by at/by (avoids matching bare numbers)
    tryPattern(
      RegExp(r'\b(?:at|by|around)\s+([01]?\d|2[0-3]):([0-5]\d)\b',
          caseSensitive: false),
      (m) {
        final h = int.parse(m.group(1)!);
        final min = int.parse(m.group(2)!);
        var dt = DateTime(now.year, now.month, now.day, h, min);
        if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
        return dt;
      },
    );

    if (candidates.isEmpty) return TimeMatch.none(text);

    // Earliest match in the string wins.
    candidates.sort((a, b) => a.$1.start.compareTo(b.$1.start));
    final (match, remindAt) = candidates.first;
    final cleaned = (text.substring(0, match.start) + text.substring(match.end))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return TimeMatch(remindAt: remindAt, cleanedText: cleaned, matched: true);
  }
}
