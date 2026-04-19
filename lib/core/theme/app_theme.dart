import 'package:flutter/material.dart';

class AppColors {
  static const tealStart = Color(0xFF22D3EE);
  static const tealEnd = Color(0xFF2DD4BF);
  static const heroBg = Color(0xFF0F1923);
  static const bgContent = Color(0xFFF8F9FA);
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF757575);
  static const cardBg = Colors.white;
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.tealStart,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.bgContent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.textPrimary),
      ),
    );
  }
}

class ReaderTheme {
  final Color bg;
  final Color text;
  final String name;

  const ReaderTheme({required this.bg, required this.text, required this.name});

  static const white = ReaderTheme(
    bg: Colors.white, text: Color(0xFF1A1A1A), name: 'Trắng');
  static const sepia = ReaderTheme(
    bg: Color(0xFFF5E6C8), text: Color(0xFF3E2723), name: 'Sepia');
  static const dark = ReaderTheme(
    bg: Color(0xFF1A1A2E), text: Color(0xFFE0E0E0), name: 'Tối');
  static const cream = ReaderTheme(
    bg: Color(0xFFEAE4D3), text: Color(0xFF3E2723), name: 'Kem');

  static const all = [white, sepia, cream, dark];
}
