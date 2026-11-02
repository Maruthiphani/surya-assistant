import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surya/services/intent_channel.dart';

/// Locks the Dart side of the Siri Shortcut bridge (CLAUDE.md Phase 5). The
/// native half (AppDelegate.swift + SuryaIntents.swift) can only be exercised
/// on a device, so these tests pin the method-channel contract it must honour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'surya/intents';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('IntentChannel.consumePending', () {
    tearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel(channelName), null);
    });

    test('returns trimmed pending text from the native side', () async {
      messenger.setMockMethodCallHandler(const MethodChannel(channelName),
          (call) async {
        expect(call.method, 'consumePendingReminder');
        return '  remind me to buy milk at Walmart  ';
      });

      final text = await IntentChannel().consumePending();
      expect(text, 'remind me to buy milk at Walmart');
    });

    test('returns null when nothing is pending', () async {
      messenger.setMockMethodCallHandler(
          const MethodChannel(channelName), (call) async => null);

      expect(await IntentChannel().consumePending(), isNull);
    });

    test('returns null when there is no native handler (non-iOS)', () async {
      // No mock handler registered → MissingPluginException → graceful null.
      expect(await IntentChannel().consumePending(), isNull);
    });
  });

  group('IntentChannel.onPrefill', () {
    test('warm-start prefillReminder call reaches the handler', () async {
      String? received;
      IntentChannel().onPrefill((text) => received = text);

      // Simulate the native side invoking the method on the Dart handler.
      await messenger.handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('prefillReminder', 'buy eggs at Target'),
        ),
        (_) {},
      );

      expect(received, 'buy eggs at Target');
    });
  });
}
