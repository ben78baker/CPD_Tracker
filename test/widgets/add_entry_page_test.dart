import 'package:cpd_tracker/add_entry_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
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
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: AppTheme.light,
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

    expect(find.byType(TactileButton), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Save Entry'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Save Entry'), findsOneWidget);
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
}
