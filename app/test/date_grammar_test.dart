import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/recurrence.dart';
import 'package:surya/parsing/date_grammar.dart';

/// Phase 8: absolute date + recurrence recognition (the complement to
/// TimeGrammar). Pure, so it tests directly.
void main() {
  final now = DateTime(2026, 6, 15, 9, 0); // Mon 15 Jun 2026

  group('absolute dates', () {
    test('"November 7" → that date this year, stripped from text', () {
      final m = DateGrammar.extract('wish mom happy birthday on november 7', now);
      expect(m.matched, isTrue);
      expect(m.date, DateTime(2026, 11, 7));
      expect(m.recurrence, Recurrence.none);
      expect(m.cleanedText, 'wish mom happy birthday'); // dangling "on" tidied
    });

    test('"7th of December" day-month order', () {
      final m = DateGrammar.extract('pay rent 7th of december', now);
      expect(m.date, DateTime(2026, 12, 7));
    });

    test('a date already past this year rolls to next year', () {
      final m = DateGrammar.extract('call the dentist on jan 10', now);
      expect(m.date, DateTime(2027, 1, 10));
    });

    test('numeric 12/25', () {
      final m = DateGrammar.extract('12/25', now);
      expect(m.date, DateTime(2026, 12, 25));
    });
  });

  group('recurrence', () {
    test('"every November 7" → yearly on that date', () {
      final m = DateGrammar.extract('every november 7', now);
      expect(m.recurrence, Recurrence.yearly);
      expect(m.date, DateTime(2026, 11, 7));
    });

    test('"daily" / "every day"', () {
      expect(DateGrammar.extract('take pills daily', now).recurrence,
          Recurrence.daily);
      expect(DateGrammar.extract('water plants every day', now).recurrence,
          Recurrence.daily);
    });

    test('"every Monday" → weekly anchored to that weekday', () {
      final m = DateGrammar.extract('team sync every monday', now);
      expect(m.recurrence, Recurrence.weekly);
      expect(m.date!.weekday, DateTime.monday);
    });

    test('"weekly" / "monthly" / "annually"', () {
      expect(DateGrammar.extract('groceries weekly', now).recurrence,
          Recurrence.weekly);
      expect(DateGrammar.extract('pay rent monthly', now).recurrence,
          Recurrence.monthly);
      expect(DateGrammar.extract('taxes annually', now).recurrence,
          Recurrence.yearly);
    });
  });

  test('no date/recurrence → unmatched, text unchanged', () {
    final m = DateGrammar.extract('buy milk at walmart', now);
    expect(m.matched, isFalse);
    expect(m.cleanedText, 'buy milk at walmart');
    expect(m.date, isNull);
    expect(m.recurrence, Recurrence.none);
  });
}
