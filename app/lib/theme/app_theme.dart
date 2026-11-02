import 'package:flutter/material.dart';

/// Centralised theme definitions for the app.
///
/// Keeping colours and typography in one place (instead of scattered inline
/// [ThemeData] objects) makes it trivial to tweak branding later and keeps
/// every screen visually consistent. Material 3 is enabled throughout.
class AppTheme {
  AppTheme._(); // Not instantiable — this is a namespace for static theme data.

  /// Brand seed colour. All light/dark colour schemes are derived from this,
  /// so changing one line re-themes the whole app.
  static const Color _seed = Color(0xFF4C5BD4);

  static ThemeData get light => _base(Brightness.light);

  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
    );
  }
}
