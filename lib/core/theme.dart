import 'package:flutter/material.dart';

abstract final class LG {
  static const bg = Color(0xFF121513),
      lime = Color(0xFFB9F34A),
      light = Color(0xFFF3F4EF),
      surface = Color(0xFF1C1F1D),
      muted = Color(0xFF929892),
      orange = Color(0xFFFF9F54),
      blue = Color(0xFF65D9FF);
  static ThemeData theme({bool dark = true}) => ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: dark ? bg : light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: lime,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: dark ? lime : bg,
      surface: dark ? surface : Colors.white,
    ),
    fontFamily: 'Inter',
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? bg : light,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
  );
}
