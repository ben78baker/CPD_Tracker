import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:cpd_tracker/widgets/tactile_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tactile button depresses and releases using a Material button', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: TactileButton(
              onPressed: () => presses++,
              variant: TactileButtonVariant.primary,
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );

    final surface = find.descendant(
      of: find.byType(TactileButton),
      matching: find.byType(AnimatedContainer),
    );
    expect(surface, findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );

    double verticalTranslation() {
      final transform = tester.widget<AnimatedContainer>(surface).transform!;
      return transform.storage[13];
    }

    expect(verticalTranslation(), 0);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Save')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(verticalTranslation(), closeTo(2, 0.01));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 160));
    expect(verticalTranslation(), closeTo(0, 0.01));
    expect(presses, 1);
  });

  testWidgets(
    'disabled tactile button stays disabled and keeps a large target',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Center(
              child: TactileButton(onPressed: null, child: Text('Unavailable')),
            ),
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
    },
  );

  testWidgets('neutral surface keeps accent details and press feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: TactileButton(
              onPressed: () {},
              variant: TactileButtonVariant.primary,
              surfaceTreatment: TactileButtonSurfaceTreatment.neutral,
              child: const Text('Add Evidence'),
            ),
          ),
        ),
      ),
    );

    ButtonStyle buttonStyle() =>
        tester.widget<FilledButton>(find.byType(FilledButton)).style!;

    expect(
      buttonStyle().backgroundColor!.resolve(<WidgetState>{}),
      AppColors.surface,
    );
    expect(
      buttonStyle().foregroundColor!.resolve(<WidgetState>{}),
      AppColors.brandPurpleDark,
    );
    expect(
      buttonStyle().side!.resolve(<WidgetState>{})!.color,
      AppColors.brandPurple,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Add Evidence')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      buttonStyle().backgroundColor!.resolve(<WidgetState>{}),
      AppColors.brandPurpleSoft,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 160));
  });
}
