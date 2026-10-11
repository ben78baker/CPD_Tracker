import 'package:flutter/material.dart';

import 'app_accent.dart';

abstract final class AppColors {
  static const Color brandPurple = Color(0xFF9043CD);
  static const Color brandPurpleDark = Color(0xFF6B249F);
  static const Color brandPurpleLight = Color(0xFFF1E6F8);
  static const Color brandPurpleSoft = Color(0xFFE9D7F4);
  static const Color brandPurpleWash = Color(0xFFF7F2FB);
  static const Color onBrandPurpleLight = Color(0xFF321044);
  static const Color secondaryPurple = Color(0xFF6F58A8);
  static const Color secondaryPurpleLight = Color(0xFFEDE7F6);
  static const Color controlSurface = Color(0xFFFCFAFD);
  static const Color controlEdge = Color(0xFFB99DC8);

  static const Color canvas = Color(0xFFF8F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF211D24);
  static const Color outline = Color(0xFF9A79AA);
  static const Color outlineVariant = Color(0xFFD9CCE2);
}

abstract final class AppGradients {
  static LinearGradient pageHeader(AppBrandColors brand) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[brand.accentSoft, brand.accentWash, AppColors.canvas],
    stops: const <double>[0, 0.62, 1],
  );

  static LinearGradient cardHeader(AppBrandColors brand) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[brand.accentLight, brand.accentWash, AppColors.surface],
    stops: const <double>[0, 0.72, 1],
  );
}

@immutable
class AppBrandColors extends ThemeExtension<AppBrandColors> {
  const AppBrandColors({
    required this.accent,
    required this.accentDark,
    required this.accentLight,
    required this.accentSoft,
    required this.accentWash,
    required this.onAccentLight,
    required this.secondary,
    required this.secondaryLight,
    required this.outline,
    required this.outlineVariant,
    required this.controlSurface,
    required this.controlEdge,
  });

  factory AppBrandColors.fromAccent(AppAccent selected) {
    if (selected == AppAccent.purple) {
      return const AppBrandColors(
        accent: AppColors.brandPurple,
        accentDark: AppColors.brandPurpleDark,
        accentLight: AppColors.brandPurpleLight,
        accentSoft: AppColors.brandPurpleSoft,
        accentWash: AppColors.brandPurpleWash,
        onAccentLight: AppColors.onBrandPurpleLight,
        secondary: AppColors.secondaryPurple,
        secondaryLight: AppColors.secondaryPurpleLight,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        controlSurface: AppColors.controlSurface,
        controlEdge: AppColors.controlEdge,
      );
    }

    final scheme = ColorScheme.fromSeed(
      seedColor: selected.seedColor,
      brightness: Brightness.light,
    );
    return AppBrandColors(
      accent: scheme.primary,
      accentDark: scheme.onPrimaryContainer,
      accentLight: scheme.primaryContainer,
      accentSoft: Color.lerp(scheme.primaryContainer, scheme.primary, 0.10)!,
      accentWash: Color.lerp(AppColors.canvas, scheme.primaryContainer, 0.42)!,
      onAccentLight: scheme.onPrimaryContainer,
      secondary: scheme.secondary,
      secondaryLight: scheme.secondaryContainer,
      outline: Color.lerp(scheme.outline, scheme.primary, 0.25)!,
      outlineVariant: Color.lerp(
        scheme.outlineVariant,
        scheme.primaryContainer,
        0.28,
      )!,
      controlSurface: Color.lerp(
        AppColors.surface,
        scheme.primaryContainer,
        0.14,
      )!,
      controlEdge: Color.lerp(scheme.outline, scheme.primary, 0.42)!,
    );
  }

  final Color accent;
  final Color accentDark;
  final Color accentLight;
  final Color accentSoft;
  final Color accentWash;
  final Color onAccentLight;
  final Color secondary;
  final Color secondaryLight;
  final Color outline;
  final Color outlineVariant;
  final Color controlSurface;
  final Color controlEdge;

  @override
  AppBrandColors copyWith({
    Color? accent,
    Color? accentDark,
    Color? accentLight,
    Color? accentSoft,
    Color? accentWash,
    Color? onAccentLight,
    Color? secondary,
    Color? secondaryLight,
    Color? outline,
    Color? outlineVariant,
    Color? controlSurface,
    Color? controlEdge,
  }) {
    return AppBrandColors(
      accent: accent ?? this.accent,
      accentDark: accentDark ?? this.accentDark,
      accentLight: accentLight ?? this.accentLight,
      accentSoft: accentSoft ?? this.accentSoft,
      accentWash: accentWash ?? this.accentWash,
      onAccentLight: onAccentLight ?? this.onAccentLight,
      secondary: secondary ?? this.secondary,
      secondaryLight: secondaryLight ?? this.secondaryLight,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      controlSurface: controlSurface ?? this.controlSurface,
      controlEdge: controlEdge ?? this.controlEdge,
    );
  }

  @override
  AppBrandColors lerp(covariant AppBrandColors? other, double t) {
    if (other == null) return this;
    return AppBrandColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentDark: Color.lerp(accentDark, other.accentDark, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      onAccentLight: Color.lerp(onAccentLight, other.onAccentLight, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryLight: Color.lerp(secondaryLight, other.secondaryLight, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      controlSurface: Color.lerp(controlSurface, other.controlSurface, t)!,
      controlEdge: Color.lerp(controlEdge, other.controlEdge, t)!,
    );
  }
}

extension AppBrandContext on BuildContext {
  AppBrandColors get brandColors {
    return Theme.of(this).extension<AppBrandColors>() ??
        AppBrandColors.fromAccent(AppAccent.purple);
  }
}

class AppTheme {
  static const double _controlRadius = 12;
  static const double _cardRadius = 16;

  static ThemeData get light => forAccent(AppAccent.purple);

  static ThemeData forAccent(AppAccent selected) {
    final brand = AppBrandColors.fromAccent(selected);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: brand.accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: brand.accent,
          onPrimary: Colors.white,
          primaryContainer: brand.accentLight,
          onPrimaryContainer: brand.onAccentLight,
          secondary: brand.secondary,
          onSecondary: Colors.white,
          secondaryContainer: brand.secondaryLight,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          outline: brand.outline,
          outlineVariant: brand.outlineVariant,
        );

    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    final textTheme = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    );

    final enabledInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
      borderSide: BorderSide(color: brand.outline, width: 1),
    );
    final focusedInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
      borderSide: BorderSide(color: brand.accent, width: 2),
    );
    final errorInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
      borderSide: BorderSide(color: colorScheme.error, width: 1),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.onSurface,
        ),
      ),
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: BorderSide(color: brand.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: enabledInputBorder,
        enabledBorder: enabledInputBorder,
        focusedBorder: focusedInputBorder,
        errorBorder: errorInputBorder,
        focusedErrorBorder: errorInputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand.accentLight,
          foregroundColor: brand.accentDark,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          side: BorderSide(color: brand.accent),
          elevation: 1,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: brand.accentDark,
          backgroundColor: brand.controlSurface,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand.accentDark,
          backgroundColor: brand.controlSurface,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          side: BorderSide(color: brand.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand.accentDark,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: textTheme.labelLarge,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand.accent,
        linearTrackColor: brand.accentLight,
        circularTrackColor: brand.accentLight,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: brand.accent,
        selectionColor: brand.accent.withValues(alpha: 0.25),
        selectionHandleColor: brand.accent,
      ),
      dividerColor: brand.outlineVariant,
      focusColor: brand.accent.withValues(alpha: 0.12),
      extensions: <ThemeExtension<dynamic>>[brand],
    );
  }
}
