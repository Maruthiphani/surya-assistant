import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/reminder.dart';
import 'package:surya/services/ai_service.dart';
import 'package:surya/services/parsing_metrics.dart';
import 'package:surya/services/reminder_composer.dart';

class FakeAiService implements AiService {
  int parseCalls = 0;
  bool throwOnParse = false;
  ParseResult next = const ParseResult(
    task: 'buy rice',
    locationType: LocationType.query,
    locationName: 'Costco',
    locationQuery: 'Costco',
  );

  @override
  Future<ParseResult> parse(String text, {double? lat, double? lng}) async {
    parseCalls++;
    if (throwOnParse) throw const AiServiceException('offline');
    return next;
  }

  @override
  Future<List<PlaceCandidate>> nearby(String query, double lat, double lng,
          {int radiusMeters = 30000, int limit = 20}) async =>
      [];

  @override
  Future<String> confirm(String task, String locationName, String assistantName) async =>
      'ok';
}

void main() {
  late FakeAiService ai;
  late ParsingMetrics metrics;
  late ReminderComposer composer;

  setUp(() {
    ai = FakeAiService();
    metrics = ParsingMetrics();
    composer = ReminderComposer(aiService: ai, metrics: metrics);
  });

  test('RESOLVED locally — no LLM call', () async {
    final r = await composer.compose('Remind me to buy milk at Walmart.');
    expect(r, isA<ComposeResolved>());
    final res = r as ComposeResolved;
    expect(res.fromFallback, isFalse);
    expect(res.draft.task, 'buy milk');
    expect(res.draft.locationType, LocationType.query);
    expect(ai.parseCalls, 0); // local path never hit the backend
    expect(metrics.localResolved, 1);
  });

  test('CLARIFY locally — no LLM call', () async {
    final r = await composer.compose('Remind me when I reach home.');
    expect(r, isA<ComposeClarify>());
    expect(ai.parseCalls, 0);
    expect(metrics.localClarify, 1);
  });

  test('UNPARSEABLE — falls back to the LLM', () async {
    final r = await composer.compose('Remind me to grab coffee at the cafe');
    expect(r, isA<ComposeResolved>());
    expect((r as ComposeResolved).fromFallback, isTrue);
    expect(ai.parseCalls, 1);
    expect(metrics.llmFallback, 1);
  });

  test('LLM result is cached (time-stripped key) — no second call', () async {
    await composer.compose('Remind me to grab coffee at the cafe tomorrow');
    await composer.compose('Remind me to grab coffee at the cafe'); // same minus time
    expect(ai.parseCalls, 1); // second served from cache
  });

  test('offline + unparseable -> ComposeFailed, not a bad reminder', () async {
    ai.throwOnParse = true;
    final r = await composer.compose('Some weird ungrammatical thing xyzzy');
    expect(r, isA<ComposeFailed>());
    expect(metrics.errors, 1);
  });
}
