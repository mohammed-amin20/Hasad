import 'package:flutter/material.dart';

abstract final class HasadPalette {
  static const navy = Color(0xFF132038);
  static const navyDeep = Color(0xFF0A1120);
  static const amber = Color(0xFFF08A1E);
  static const amberDark = Color(0xFFB45309);
  static const canvas = Color(0xFFF6F7F9);
  static const ink = Color(0xFF182235);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);
}

abstract final class HasadTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: HasadPalette.amberDark,
      brightness: Brightness.light,
      primary: HasadPalette.amberDark,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: HasadPalette.canvas,
      dividerColor: HasadPalette.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: HasadPalette.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HasadPalette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HasadPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HasadPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HasadPalette.amberDark, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HasadPalette.amberDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: Typography.material2021().black.apply(
        bodyColor: HasadPalette.ink,
        displayColor: HasadPalette.ink,
      ),
    );
  }
}
