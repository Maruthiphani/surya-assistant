import 'package:flutter_test/flutter_test.dart';
import 'package:surya/parsing/time_grammar.dart';

void main() {
  final now = DateTime(2026, 6, 15, 9, 0); // Monday 09:00

  test('clock "at 5 pm" is matched and removed', () {
    final r = TimeGrammar.extract('call mom at 5 pm', now);
    expect(r.matched, isTrue);
    expect(r.remindAt!.hour, 17);
    expect(r.cleanedText, 'call mom'); // "at 5 pm" stripped
  });

  test('"tomorrow morning" resolves to next-day 08:00 and is removed', () {
    final r = TimeGrammar.extract('tomorrow morning to take out the trash', now);
    expect(r.matched, isTrue);
    expect(r.remindAt!.day, 16);
    expect(r.remindAt!.hour, 8);
    expect(r.cleanedText, 'to take out the trash');
  });

  test('"in 2 hours" is relative to now', () {
    final r = TimeGrammar.extract('to leave in 2 hours', now);
    expect(r.matched, isTrue);
    expect(r.remindAt, now.add(const Duration(hours: 2)));
  });

  test('a past clock time rolls to tomorrow', () {
    final r = TimeGrammar.extract('at 8 am', now); // 8am already passed (now 9am)
    expect(r.remindAt!.day, 16);
    expect(r.remindAt!.hour, 8);
  });

  test('no time -> unmatched, text unchanged', () {
    final r = TimeGrammar.extract('buy rice at costco', now);
    expect(r.matched, isFalse);
    expect(r.cleanedText, 'buy rice at costco');
  });
}
