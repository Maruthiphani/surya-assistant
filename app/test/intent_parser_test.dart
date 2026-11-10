import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/parsed_intent.dart';
import 'package:surya/models/recurrence.dart';
import 'package:surya/models/reminder.dart';
import 'package:surya/parsing/intent_parser.dart';

void main() {
  const parser = IntentParser();
  // Fixed reference time so relative-time tests are deterministic.
  final now = DateTime(2026, 6, 15, 9, 0); // Monday 09:00

  ParsedIntent parse(String s) => parser.parse(s, now: now);

  group('RESOLVED — task + location', () {
    test('dynamic chain: buy rice at Costco', () {
      final r = parse('Remind me to buy rice at Costco.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.task, 'buy rice');
      expect(r.locationText, 'costco');
      expect(r.locationType, LocationType.query);
      expect(r.remindAt, isNull);
    });

    test('dynamic chain: buy milk at Walmart', () {
      final r = parse('Remind me to buy milk at Walmart.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.task, 'buy milk');
      expect(r.locationType, LocationType.query);
    });

    test('specific place via disambiguator: Costco in Cumming', () {
      final r = parse('Remind me to buy rice at Costco in Cumming.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.locationType, LocationType.specific);
      expect(r.locationText, 'costco in cumming');
    });

    test('location + time both extracted: Costco tomorrow', () {
      final r = parse('Remind me to buy rice at Costco tomorrow.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.task, 'buy rice');
      expect(r.locationType, LocationType.query);
      expect(r.remindAt, isNotNull); // time recognised, location still the trigger
      expect(r.remindAt!.day, 16); // tomorrow
    });
  });

  group('Accuracy — time is a trigger, not a location (Phase 8)', () {
    test('call Mom at 5 PM -> RESOLVED time reminder, no location', () {
      final r = parse('Remind me to call Mom at 5 PM.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.task, 'call mom');
      expect(r.locationText, isNull); // 5 PM is NOT treated as a place
      expect(r.remindAt, isNotNull);
      expect(r.remindAt!.hour, 17);
      expect(r.recurrence, Recurrence.none);
    });

    test('tomorrow morning ... trash -> RESOLVED time reminder', () {
      final r = parse('Remind me tomorrow morning to take out the trash.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.task, 'take out the trash');
      expect(r.locationText, isNull);
      expect(r.remindAt, isNotNull);
      expect(r.remindAt!.day, 16);
      expect(r.remindAt!.hour, 8); // "morning"
    });
  });

  group('Date & recurrence (Phase 8)', () {
    test('birthday: on November 7 every year -> yearly time reminder', () {
      final r = parse(
          'Remind me to wish mom happy birthday on November 7 every year.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.task, 'wish mom happy birthday');
      expect(r.recurrence, Recurrence.yearly);
      expect(r.remindAt, isNotNull);
      expect(r.remindAt!.month, 11);
      expect(r.remindAt!.day, 7);
    });

    test('recurrence without a time -> CLARIFY asks for the time', () {
      final r = parse('Remind me to take my pills daily.');
      expect(r.outcome, ParseOutcome.clarify);
      expect(r.task, 'take my pills');
      expect(r.recurrence, Recurrence.daily);
      expect(r.remindAt, isNull);
      expect(r.clarifyPrompt, contains('time'));
    });

    test('date + explicit time combine', () {
      final r = parse('Remind me to call the bank on December 1 at 10 am.');
      expect(r.outcome, ParseOutcome.resolved);
      expect(r.remindAt!.month, 12);
      expect(r.remindAt!.day, 1);
      expect(r.remindAt!.hour, 10);
    });
  });

  group('CLARIFY — one slot missing', () {
    test('location only (no task): when I reach home', () {
      final r = parse('Remind me when I reach home.');
      expect(r.outcome, ParseOutcome.clarify);
      expect(r.hasTask, isFalse);
      expect(r.locationText, 'home');
      expect(r.locationType, LocationType.specific);
      expect(r.clarifyPrompt, contains('What should I remind you'));
    });
  });

  group('UNPARSEABLE — fall back to the LLM', () {
    test('no reminder anchor', () {
      expect(parse('What is the weather today?').outcome,
          ParseOutcome.unparseable);
    });

    test('multiple instructions (two places)', () {
      expect(parse('Remind me to buy rice at Costco and milk at Walmart').outcome,
          ParseOutcome.unparseable);
    });

    test('explicit multi-clause connector', () {
      expect(parse('Remind me to buy rice at Costco then call Mom').outcome,
          ParseOutcome.unparseable);
    });

    test('unknown place (not a known chain/category, no disambiguator)', () {
      expect(parse('Remind me to grab coffee at the cafe').outcome,
          ParseOutcome.unparseable);
    });
  });
}
