import 'package:flutter/material.dart';

class AppColors {
  // ── Brand accent (navy) ────────────────────────────────────────────────────
  static const accent      = Color(0xFF1E3A8A); // navy chủ đạo
  static const accentLight = Color(0xFF2563EB); // navy nhạt hơn cho hover/gradient
  // ── Legacy aliases (giữ để không break các màn hình khác) ─────────────────
  static const tealStart = accent;
  static const tealEnd   = accentLight;
  // ── Neutrals ──────────────────────────────────────────────────────────────
  static const heroBg        = Color(0xFF0F172A); // dark navy cho overlay
  static const bgContent     = Color(0xFFF8F9FA); // nền xám nhạt — giữ nguyên
  static const textPrimary   = Color(0xFF0F172A); // đen xanh đậm
  static const textSecondary = Color(0xFF6B7280); // xám trung tính
  static const cardBg        = Colors.white;
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
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
