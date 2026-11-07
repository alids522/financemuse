import 'package:flutter/material.dart';

/// Design tokens — PRD §8.2. Professional minimal fintech, no neon/glass/glow.
/// Font: Inter with platform sans fallback (no bundled font asset; the build
/// must never block on the font).
class AppColors {
  // Dark
  static const darkBg = Color(0xFF101317);
  static const darkSurface = Color(0xFF191D22);
  static const darkElevated = Color(0xFF22272D);
  static const darkBorder = Color(0xFF30363D);
  static const darkText = Color(0xFFEDF0F2);
  static const darkSecondary = Color(0xFF9BA4AE);
  static const darkAccent = Color(0xFF7B9BC0);
  static const darkPositive = Color(0xFF72B39A);
  static const darkNegative = Color(0xFFD88989);
  static const darkWarning = Color(0xFFD6B071);

  // Light
  static const lightBg = Color(0xFFF7F8FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightElevated = Color(0xFFEFF2F5);
  static const lightBorder = Color(0xFFDFE3E8);
  static const lightText = Color(0xFF20252B);
  static const lightSecondary = Color(0xFF68727D);
  static const lightAccent = Color(0xFF456D9A);
  static const lightPositive = Color(0xFF287C60);
  static const lightNegative = Color(0xFFB64D52);
  static const lightWarning = Color(0xFFA76A22);
}

/// Spacing scale PRD §8.2: 4, 8, 12, 16, 24, 32.
class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double radius = 8;
}

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
  final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
  final elevated = isDark ? AppColors.darkElevated : AppColors.lightElevated;
  final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
  final text = isDark ? AppColors.darkText : AppColors.lightText;
  final secondary = isDark ? AppColors.darkSecondary : AppColors.lightSecondary;
  final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
  final positive = isDark ? AppColors.darkPositive : AppColors.lightPositive;
  final negative = isDark ? AppColors.darkNegative : AppColors.lightNegative;

  const fontFamily = 'Inter';
  final baseText = TextTheme(
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: text),
    bodyLarge: TextStyle(fontSize: 14, height: 1.5, color: text),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: secondary),
    titleLarge: TextStyle(
        fontSize: 28, height: 1.3, fontWeight: FontWeight.w600, color: text),
    titleMedium: TextStyle(
        fontSize: 22, height: 1.3, fontWeight: FontWeight.w600, color: text),
    titleSmall: TextStyle(
        fontSize: 18, height: 1.4, fontWeight: FontWeight.w600, color: text),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondary),
  );

  return ThemeData(
    brightness: brightness,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: isDark ? AppColors.darkText : Colors.white,
      secondary: accent,
      onSecondary: isDark ? AppColors.darkText : Colors.white,
      error: negative,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
    ),
    textTheme: baseText,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: elevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        borderSide: BorderSide(color: negative),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(color: secondary),
      helperStyle: TextStyle(color: secondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: isDark ? AppColors.darkText : Colors.white,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(0, 44),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      ),
    ),
    dividerColor: border,
    extensions: [
      FinanceColors(positive: positive, negative: negative,
          warning: isDark ? AppColors.darkWarning : AppColors.lightWarning),
    ],
  );
}

@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.positive,
    required this.negative,
    required this.warning,
  });
  final Color positive;
  final Color negative;
  final Color warning;

  @override
  FinanceColors copyWith({Color? positive, Color? negative, Color? warning}) =>
      FinanceColors(
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
        warning: warning ?? this.warning,
      );

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension FinanceColorsOf on BuildContext {
  FinanceColors get finance =>
      Theme.of(this).extension<FinanceColors>()!;
}
