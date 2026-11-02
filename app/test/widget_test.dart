// Smoke test: with no signed-in user, the app shows the login screen.
//
// We override `authStateProvider` to emit `null` so the test never touches real
// Firebase. Expanded as more screens gain coverage.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:surya/app.dart';
import 'package:surya/providers/providers.dart';

void main() {
  testWidgets('Shows login screen when signed out', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No user -> AuthGate should render LoginScreen.
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const SuryaApp(),
      ),
    );
    // Let the stream emit and the gate rebuild.
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
