import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme uses the CPD brand foundation', () {
    final theme = AppTheme.light;

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, AppColors.brandPurple);
    expect(theme.colorScheme.primaryContainer, AppColors.brandPurpleLight);
    expect(theme.scaffoldBackgroundColor, AppColors.canvas);

    final focusedBorder =
        theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
    expect(focusedBorder.borderSide.color, AppColors.brandPurple);
    expect(focusedBorder.borderSide.width, 2);

    final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(cardShape.borderRadius, BorderRadius.circular(16));
    expect(cardShape.side.color, AppColors.outlineVariant);

    final filledButtonStyle = theme.filledButtonTheme.style!;
    expect(
      filledButtonStyle.backgroundColor!.resolve(<WidgetState>{}),
      AppColors.brandPurpleLight,
    );
    expect(
      filledButtonStyle.foregroundColor!.resolve(<WidgetState>{}),
      AppColors.brandPurpleDark,
    );
    expect(
      filledButtonStyle.minimumSize!.resolve(<WidgetState>{}),
      const Size(64, 48),
    );

    expect(theme.progressIndicatorTheme.color, AppColors.brandPurple);
  });

  test('curated accent themes provide readable pale-container text', () {
    for (final accent in AppAccent.values) {
      final brand = AppBrandColors.fromAccent(accent);
      expect(
        _contrastRatio(brand.onAccentLight, brand.accentLight),
        greaterThanOrEqualTo(4.5),
        reason: '${accent.name} should retain normal-text contrast',
      );
      expect(AppTheme.forAccent(accent).colorScheme.primary, brand.accent);
    }
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}
