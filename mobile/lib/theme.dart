import 'package:flutter/material.dart';

abstract final class DamaColors {
  static const cream = Color(0xFFF7F5EE);
  static const paper = Color(0xFFFFFEF9);
  static const forest = Color(0xFF244F3B);
  static const forestDark = Color(0xFF153C2A);
  static const copper = Color(0xFFBF754D);
  static const ink = Color(0xFF213E33);
  static const muted = Color(0xFF737D69);
  static const line = Color(0xFFE1E3D6);
}

ThemeData damaTheme({bool dark = false}) {
  final background = dark ? const Color(0xFF14251F) : DamaColors.cream;
  final surface = dark ? const Color(0xFF1D3028) : DamaColors.paper;
  final foreground = dark ? const Color(0xFFEEEEDD) : DamaColors.ink;
  final line = dark ? const Color(0xFF35473A) : DamaColors.line;
  final scheme = ColorScheme.fromSeed(
    seedColor: DamaColors.forest,
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: dark ? const Color(0xFFA7C790) : DamaColors.forest,
    secondary: dark ? const Color(0xFFDAA17B) : DamaColors.copper,
    surface: surface,
    onSurface: foreground,
    outline: line,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansArabic',
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansArabic',
        color: foreground,
        fontWeight: FontWeight.w700,
        fontSize: 19,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: dark ? const Color(0xFF1C3323) : DamaColors.paper,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: 'NotoSansArabic',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 46),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A2C23) : const Color(0xFFF8F9F2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DamaColors.forestDark,
      contentTextStyle: const TextStyle(
        fontFamily: 'NotoSansArabic',
        color: Colors.white,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
