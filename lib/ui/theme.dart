import 'package:flutter/material.dart';

/// Colours and type from DACS Attendance (ui/theme/Color.kt), so the two
/// apps look like one company while workers switch over.
class WmColors {
  static const green = Color(0xFF1A5C3A);
  static const greenTint = Color(0xFFEAF2EC);
  static const brown = Color(0xFF7C5E2A);
  static const brownTint = Color(0xFFF5EFE3);
  static const danger = Color(0xFFC0392B);
  static const dangerBorder = Color(0xFFF2DFDC);
  static const dangerTint = Color(0xFFFDF5F4);
  static const canvas = Color(0xFFF6F7F4);
  static const field = Color(0xFFF4F5F1);
  static const border = Color(0xFFE6E7E1);
  static const hairline = Color(0xFFF0F0EB);
  static const text = Color(0xFF1B1B19);
  static const textSecondary = Color(0xFF3A3A37);
  static const textMuted = Color(0xFF7A7A75);
  static const textMeta = Color(0xFF8A8A86);
  static const inert = Color(0xFFEDEDE8);
}

ThemeData workMateTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'Barlow',
      scaffoldBackgroundColor: WmColors.canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: WmColors.green, primary: WmColors.green, surface: WmColors.canvas),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WmColors.field,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: WmColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: WmColors.border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WmColors.green,
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
    );

const monoLabel = TextStyle(fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1.2, color: WmColors.textMeta);
