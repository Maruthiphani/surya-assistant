import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/recurrence.dart';

/// Phase 8: the next-occurrence math is pure, so it tests directly. These are
/// the rules that make "every November 7" fire next year, and monthly-on-the-
/// 31st land on short months correctly.
void main() {
  group('nextOccurrence', () {
    final now = DateTime(2026, 11, 5, 12, 0); // Thu 5 Nov 2026, noon

    test('none: future one-shot returns itself; past returns null', () {
      final future = DateTime(2026, 11, 7, 9, 0);
      final past = DateTime(2026, 11, 1, 9, 0);
      expect(Recurrence.none.nextOccurrence(future, after: now), future);
      expect(Recurrence.none.nextOccurrence(past, after: now), isNull);
    });

    test('daily advances to the next day past now', () {
      final anchor = DateTime(2026, 11, 1, 7, 0); // 07:00, already past today
      final next = Recurrence.daily.nextOccurrence(anchor, after: now)!;
      expect(next, DateTime(2026, 11, 6, 7, 0)); // tomorrow 07:00
    });

    test('weekly keeps the weekday', () {
      final anchor = DateTime(2026, 11, 2, 9, 0); // a Monday
      final next = Recurrence.weekly.nextOccurrence(anchor, after: now)!;
      expect(next.weekday, DateTime.monday);
      expect(next.isAfter(now), isTrue);
    });

    test('yearly birthday rolls to next year once this year has passed', () {
      final birthday = DateTime(2026, 11, 7, 9, 0); // still ahead of now
      expect(Recurrence.yearly.nextOccurrence(birthday, after: now), birthday);

      final passed = DateTime(2026, 11, 1, 9, 0); // already gone this year
      final next = Recurrence.yearly.nextOccurrence(passed, after: now)!;
      expect(next, DateTime(2027, 11, 1, 9, 0));
    });

    test('monthly-on-the-31st clamps to shorter months', () {
      final anchor = DateTime(2026, 1, 31, 8, 0);
      final after = DateTime(2026, 2, 1, 0, 0);
      final next = Recurrence.monthly.nextOccurrence(anchor, after: after)!;
      // February has no 31st → clamps to the 28th (2026 is not a leap year).
      expect(next, DateTime(2026, 2, 28, 8, 0));
    });

    test('labels and repeats flag', () {
      expect(Recurrence.none.repeats, isFalse);
      expect(Recurrence.yearly.repeats, isTrue);
      expect(Recurrence.yearly.label, 'Yearly');
    });

    test('wire codec round-trips and defaults safely', () {
      expect(Recurrence.fromName('weekly'), Recurrence.weekly);
      expect(Recurrence.fromName(null), Recurrence.none);
      expect(Recurrence.fromName('garbage'), Recurrence.none);
    });
  });
}
