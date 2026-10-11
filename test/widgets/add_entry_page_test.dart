import 'package:cpd_tracker/add_entry_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:cpd_tracker/widgets/form_section_tile.dart';
import 'package:cpd_tracker/widgets/tactile_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _testApp({
  required Locale locale,
  required String profession,
  AppAccent accent = AppAccent.purple,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: AppTheme.forAccent(accent),
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: AddEntryPage(profession: profession),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('form section makes descendant focus clearly visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: FormSectionTile(
            label: 'Details',
            icon: Icons.notes,
            child: TextField(),
          ),
        ),
      ),
    );

    BoxDecoration tileDecoration() {
      return tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .decoration
          as BoxDecoration;
    }

    expect(tileDecoration().border!.top.width, 1);
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tileDecoration().border!.top.color, AppColors.brandPurple);
    expect(tileDecoration().border!.top.width, 2);
  });

  testWidgets('entry form uses six distinct sections and bounded details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _testApp(locale: const Locale('en'), profession: 'Electrician'),
    );
    await tester.pump();

    expect(find.byType(FormSectionTile), findsNWidgets(6));

    final detailsField = find.byKey(const ValueKey('entry-details-field'));
    final editableText = tester.widget<EditableText>(
      find.descendant(of: detailsField, matching: find.byType(EditableText)),
    );
    expect(editableText.minLines, 4);
    expect(editableText.maxLines, 10);
    expect(editableText.keyboardType, TextInputType.multiline);
    expect(editableText.textInputAction, TextInputAction.newline);

    final dateAction = tester.widget<TactileButton>(
      find.byKey(const ValueKey('entry-date-action')),
    );
    expect(dateAction.surfaceTreatment, TactileButtonSurfaceTreatment.neutral);

    final addAttachmentAction = tester.widget<TactileButton>(
      find.byKey(const ValueKey('entry-add-attachment-action')),
    );
    expect(addAttachmentAction.variant, TactileButtonVariant.primary);
    expect(
      addAttachmentAction.surfaceTreatment,
      TactileButtonSurfaceTreatment.neutral,
    );

    expect(find.byType(TactileButton), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Save Entry'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Save Entry'), findsOneWidget);
    final saveAction = tester.widget<TactileButton>(
      find.ancestor(
        of: find.text('Save Entry'),
        matching: find.byType(TactileButton),
      ),
    );
    expect(saveAction.variant, TactileButtonVariant.primary);
    expect(saveAction.surfaceTreatment, TactileButtonSurfaceTreatment.tonal);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('de'), Locale('pt')]) {
    testWidgets(
      'entry form remains usable at narrow width and large ${locale.languageCode} text',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _testApp(
            locale: locale,
            profession:
                'Elektroinstallation, Prüfung und berufliche Weiterbildung',
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pump();

        expect(find.byType(FormSectionTile), findsNWidgets(6));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final accent in <AppAccent>[AppAccent.purple, AppAccent.teal]) {
    testWidgets(
      'entry utility overlays stay neutral with ${accent.name} accents',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _testApp(
            locale: const Locale('en'),
            profession: 'Electrician',
            accent: accent,
          ),
        );
        await tester.pump();

        final dateAction = find.descendant(
          of: find.byKey(const ValueKey('entry-date-action')),
          matching: find.byType(FilledButton),
        );
        await tester.ensureVisible(dateAction);
        await tester.tap(dateAction);
        await tester.pumpAndSettle();

        final dateDialog = tester.widget<Dialog>(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(Dialog),
          ),
        );
        expect(dateDialog.backgroundColor, AppColors.surface);
        expect(dateDialog.surfaceTintColor, Colors.transparent);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final attachmentAction = find.descendant(
          of: find.byKey(const ValueKey('entry-add-attachment-action')),
          matching: find.byType(FilledButton),
        );
        await tester.ensureVisible(attachmentAction);
        await tester.tap(attachmentAction);
        await tester.pumpAndSettle();

        final bottomSheet = tester.widget<BottomSheet>(
          find.byType(BottomSheet),
        );
        expect(bottomSheet.backgroundColor, AppColors.surface);
      },
    );
  }
}
