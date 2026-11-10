/// How a time-based reminder repeats (CLAUDE.md Phase 8).
///
/// [none] fires once. The rest repeat on the natural calendar step — [yearly]
/// is what powers "every November 7" birthday reminders.
enum Recurrence {
  none,
  daily,
  weekly,
  monthly,
  yearly;

  static Recurrence fromName(String? value) {
    return Recurrence.values.firstWhere(
      (r) => r.name == value,
      orElse: () => Recurrence.none,
    );
  }

  bool get repeats => this != Recurrence.none;

  /// Short human label for the UI ("Repeats yearly").
  String get label {
    switch (this) {
      case Recurrence.none:
        return 'Does not repeat';
      case Recurrence.daily:
        return 'Daily';
      case Recurrence.weekly:
        return 'Weekly';
      case Recurrence.monthly:
        return 'Monthly';
      case Recurrence.yearly:
        return 'Yearly';
    }
  }

  /// The first fire time strictly after [after], starting from [scheduled].
  ///
  /// - [none]: returns [scheduled] only if it's still in the future (a past
  ///   one-shot returns null → nothing to schedule).
  /// - repeating: advances by the recurrence step until it lands after [after],
  ///   clamping impossible calendar days (e.g. a monthly-on-the-31st reminder
  ///   lands on the last day of shorter months; Feb 29 yearly → Feb 28).
  DateTime? nextOccurrence(DateTime scheduled, {required DateTime after}) {
    if (this == Recurrence.none) {
      return scheduled.isAfter(after) ? scheduled : null;
    }
    var dt = scheduled;
    var guard = 0;
    while (!dt.isAfter(after) && guard < 4000) {
      dt = _advance(dt);
      guard++;
    }
    return dt;
  }

  DateTime _advance(DateTime dt) {
    switch (this) {
      case Recurrence.daily:
        return dt.add(const Duration(days: 1));
      case Recurrence.weekly:
        return dt.add(const Duration(days: 7));
      case Recurrence.monthly:
        return _addMonths(dt, 1);
      case Recurrence.yearly:
        return _addMonths(dt, 12);
      case Recurrence.none:
        return dt;
    }
  }
}

/// Add [months] calendar months, clamping the day to the target month's length
/// (so Jan 31 + 1 month = Feb 28/29, and Feb 29 + 12 months = Feb 28).
DateTime _addMonths(DateTime dt, int months) {
  final total = dt.month - 1 + months;
  final year = dt.year + (total ~/ 12);
  final month = (total % 12) + 1;
  final lastDay = DateTime(year, month + 1, 0).day; // day 0 of next month
  final day = dt.day <= lastDay ? dt.day : lastDay;
  return DateTime(year, month, day, dt.hour, dt.minute);
}
