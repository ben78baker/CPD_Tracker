import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_editor/edit_fields_page.dart';
import 'package:cpd_tracker/recording_editor/record_form.dart';
import 'package:cpd_tracker/recording_editor/template_preview.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase5_fixtures.dart';

Widget _app(
  Widget home, {
  String language = 'en',
  AppAccent accent = AppAccent.purple,
  double scaling = 1,
}) => MaterialApp(
  locale: Locale(language),
  theme: AppTheme.forAccent(accent),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scaling)),
    child: child!,
  ),
  home: home,
);

final _base = phase5Templates.first;
final _initial = LayoutRevision(
  collectionId: 'demo',
  version: 1,
  fields: _base.fields,
);

EditFieldsPage _editor(Future<LayoutRevision> Function(LayoutDraft) save) =>
    EditFieldsPage(
      title: 'Workshop and professional development',
      layout: _initial,
      save: save,
      library: phase5Library,
      maxActiveFields: 20,
      protectedDefinitionIds: {_base.fields.first.definition.id},
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final (index, locale) in [
    ...AppLocalizations.supportedLocales,
    const Locale('en'),
    const Locale('fr'),
  ].indexed) {
    testWidgets(
      'small display and large text in ${locale.languageCode} · ${AppAccent.values[index].name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            _editor((_) async => _initial),
            language: locale.languageCode,
            accent: AppAccent.values[index],
            scaling: 1.7,
          ),
        );
        await tester.pumpAndSettle();
        final s = AppLocalizations.of(
          tester.element(find.byType(EditFieldsPage)),
        )!;
        expect(find.text(s.editFields), findsOneWidget);
        expect(find.text(s.editorFullCount(5, 20)), findsOneWidget);
        expect(find.bySemanticsLabel(s.addField), findsOneWidget);
        await _tap(tester, find.byKey(const Key('open-add-field')));
        expect(find.text(s.fieldLibrary), findsOneWidget);
        await _tap(tester, find.text(s.fieldLibrary));
        expect(find.text(s.editorAll), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, s.editorSearch),
          'zzzz',
        );
        await tester.pumpAndSettle();
        expect(find.text(s.editorNoResults), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'creates a custom field and a configured library copy then moves, previews and saves',
    (tester) async {
      tester.view.physicalSize = const Size(430, 940);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final saved = <LayoutDraft>[];
      await tester.pumpWidget(
        _app(
          _editor((draft) async {
            saved.add(draft);
            return LayoutRevision(
              collectionId: 'demo',
              version: 2,
              fields: draft.fields,
              headings: draft.headings,
            );
          }),
        ),
      );
      await _tap(tester, find.byKey(const Key('open-add-field')));
      await _tap(tester, find.text('Custom field'));
      await _tap(tester, find.text('Short text'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Field name'),
        'Work order',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Required'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Add field'));
      expect(saved, isEmpty);
      await _tap(tester, find.byKey(const Key('open-add-field')));
      await _tap(tester, find.text('Field Library'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Search fields'),
        'provider',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Learning provider'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Field name'),
        'Training organiser',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Future records only'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Add field'));
      expect(find.text('7 of 20 fields'), findsOneWidget);
      await _tap(tester, find.byKey(ValueKey('menu-${_base.fields.first.id}')));
      expect(find.text('Remove field'), findsNothing);
      await _tap(tester, find.text('Move down'));
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Preview'));
      expect(
        find.text('Try sample values here. They are discarded when you leave.'),
        findsOneWidget,
      );
      await _tap(tester, find.byTooltip('Back'));
      await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(find.text('Discard changes?'), findsOneWidget);
      await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(saved, hasLength(1));
      expect(saved.single.fields[1].id, _base.fields.first.id);
      expect(
        saved.single.fields
            .singleWhere((f) => f.label == 'Work order')
            .required,
        isTrue,
      );
      final field = saved.single.fields.last;
      expect(field.label, 'Training organiser');
      expect(field.source?.id, 'activity.provider');
      expect(saved.single.includeExisting, {field.id});
    },
  );

  testWidgets(
    'template preview fields are interactive and reset without saving',
    (tester) async {
      final template = nursingPreviewTemplate(1);
      final sample = nursingCompletedExample(template);
      await tester.pumpWidget(
        _app(
          TemplatePreviewPage(
            template: template,
            profession: 'Nursing',
            country: 'UK',
            professionalBody: 'NMC',
            scheme: 'Revalidation',
            reviewed: DateTime(2026, 11, 20),
            featuresAndLimits: const [],
            examples: [sample],
            sampleReport: nursingExamplePdf,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Template version'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Try the form'), 250);
      await _tap(tester, find.text('Try the form'));
      final title = find.widgetWithText(RecordingFieldTile, 'Title');
      await tester.scrollUntilVisible(
        title,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final input = find.descendant(
        of: title,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(input, 'Temporary');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('Temporary'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await _tap(tester, find.byTooltip('Back'));
      await _tap(tester, find.text('Try the form'));
      expect(find.text('Temporary'), findsNothing);
    },
  );
}
