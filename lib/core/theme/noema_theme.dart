import 'package:flutter/material.dart';
import 'package:noema/core/theme/noema_colors.dart';

class NoemaTheme {
  const NoemaTheme._();

  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: NoemaColors.accentPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: NoemaColors.accentPrimary,
          surface: NoemaColors.surfacePrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamilyFallback: const [
        'LXGWWenKaiGB',
        'NoemaCjkFallback',
        'PingFang SC',
        'Heiti SC',
        'Noto Sans CJK SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      scaffoldBackgroundColor: NoemaColors.backgroundPrimary,
      colorScheme: colorScheme,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: NoemaColors.textPrimary,
          fontSize: 36,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
        ),
        headlineSmall: TextStyle(
          color: NoemaColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: NoemaColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: NoemaColors.textSecondary,
          fontSize: 16,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          color: NoemaColors.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      cardTheme: const CardThemeData(
        color: NoemaColors.surfacePrimary,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
