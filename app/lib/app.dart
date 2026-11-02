import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'screens/auth_gate.dart';

/// Root widget of the Surya app.
///
/// Owns the [MaterialApp] (title, theme, and the initial route). Navigation and
/// routing stay here so individual screens remain presentation-only. The home
/// target is [AuthGate], which routes between login, onboarding and home based
/// on auth + profile state.
class SuryaApp extends StatelessWidget {
  const SuryaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Surya',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}
