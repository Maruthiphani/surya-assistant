import 'package:flutter/services.dart';

/// Bridge for text handed to the app from a platform entry point — currently
/// the iOS Siri Shortcut / App Intent "tell `<name>` to remind me…" (CLAUDE.md
/// Phase 5).
///
/// Two cases are covered:
/// - **Cold start**: the app was launched by the intent. Flutter calls
///   [consumePending] once on startup to retrieve (and clear) the stored text.
/// - **Warm start**: the app was already running/backgrounded. The native side
///   pushes the text via the `prefillReminder` method, delivered to the handler
///   registered with [onPrefill].
///
/// The native implementation lives in `ios/Runner/AppDelegate.swift` +
/// `SuryaIntents.swift`. On platforms without an implementation the channel
/// simply returns null / never fires, so callers degrade gracefully.
class IntentChannel {
  IntentChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('surya/intents');

  final MethodChannel _channel;

  /// Fetch and clear any reminder text captured while the app was not running.
  /// Returns null if there's nothing pending (or no native implementation).
  Future<String?> consumePending() async {
    try {
      final text = await _channel.invokeMethod<String>('consumePendingReminder');
      final trimmed = text?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } on MissingPluginException {
      return null; // No native handler on this platform.
    } on PlatformException {
      return null;
    }
  }

  /// Register a callback for reminder text delivered while the app is running.
  /// Pass null to clear the handler.
  void onPrefill(void Function(String text)? handler) {
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'prefillReminder') {
        final text = (call.arguments as String?)?.trim();
        if (text != null && text.isNotEmpty) handler(text);
      }
      return null;
    });
  }
}
