import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Top-level router driven by auth + profile state:
///
/// - not signed in           → [LoginScreen]
/// - signed in, no profile   → [OnboardingScreen] (pick assistant name)
/// - signed in, has profile  → [HomeScreen]
///
/// Because it watches streams, navigation reacts automatically to sign-in,
/// sign-out and onboarding completion — no manual Navigator calls needed.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const _Splash(),
      error: (e, _) => _Splash(message: 'Auth error: $e'),
      data: (user) {
        if (user == null) return const LoginScreen();

        // Signed in: decide between onboarding and home based on the profile.
        final profile = ref.watch(userProfileProvider);
        return profile.when(
          loading: () => const _Splash(),
          error: (e, _) => _Splash(message: 'Profile error: $e'),
          data: (p) => p == null ? const OnboardingScreen() : const HomeScreen(),
        );
      },
    );
  }
}

/// Minimal branded loading screen shown while auth/profile resolve.
class _Splash extends StatelessWidget {
  const _Splash({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            if (message == null)
              const CircularProgressIndicator()
            else
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message!, textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
