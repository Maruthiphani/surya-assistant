import 'package:flutter_test/flutter_test.dart';
import 'package:surya/services/subscription_service.dart';

/// Locks the billing graceful-degradation contract (CLAUDE.md Phase 6): with no
/// RevenueCat key configured (the case on the test host / dev builds), the app
/// must behave as Free without ever calling the native store plugin. The free
/// cap is enforced in the UI regardless.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unconfigured service degrades to Free without touching the store', () async {
    final service = RevenueCatSubscriptionService();

    // No platform key on the test host → billing unavailable.
    expect(service.isConfigured, isFalse);

    // These must not throw or call the (unregistered) plugin.
    await service.init();
    await service.identify('test-uid');
    expect(await service.isPro(), isFalse);
    expect(await service.offerings(), isEmpty);
    await service.logOut();

    // proStatus starts with the current value (false).
    expect(await service.proStatus.first, isFalse);
  });
}
