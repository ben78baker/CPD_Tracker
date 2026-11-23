import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_editor/record_form.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LayoutField flexible(
  FieldKind kind, {
  Map<String, String> options = const {},
}) => LayoutField(
  id: 'delivery',
  definition: FieldDefinition(
    id: 'delivery',
    version: 1,
    label: 'Delivery',
    kind: kind,
    choices: const {'base': 'Workshop'},
    allowCustomOptions: true,
  ),
  addedOptions: options,
);

Widget app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('closed template fields omit Add new option', (tester) async {
    final controlled = nursingPilot.fields.where(
      (field) =>
          field.definition.kind == FieldKind.choice ||
          field.definition.kind == FieldKind.multipleChoices,
    );
    await tester.pumpWidget(
      app(
        ListView(
          children: [
            for (final field in controlled)
              RecordingFieldTile(
                field: field,
                onChanged: (_) {},
                canSaveOption: true,
                onCustomOption: (_, _) =>
                    fail('A controlled field offered a new option.'),
              ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Single choice'));
    await tester.pumpAndSettle();
    expect(find.text('Add new option'), findsNothing);
  });

  test('one-off values display without altering the historical schema', () {
    final field = flexible(FieldKind.choice);
    final raw = storeChoiceSelection((id: null, text: 'Evening session'));
    field.definition.validate(raw);
    expect(field.definition.displayValue(raw), 'Evening session');
    expect(field.definition.toJson()['choices'], {'base': 'Workshop'});
    expect(
      FieldDefinition.fromJson({
        ...field.definition.toJson(),
      }).allowCustomOptions,
      isTrue,
    );
    expect(
      FieldDefinition.fromJson(
        {...field.definition.toJson()}..remove('allowCustomOptions'),
      ).allowCustomOptions,
      isFalse,
    );
  });

  test('reusable choice labels match across whitespace and case', () {
    expect(choiceLabelKey('  Evening\t Session  '), 'evening session');
    expect(
      () => flexible(
        FieldKind.multipleChoices,
        options: {'id1': 'Evening session', 'id2': 'evening SESSION'},
      ),
      throwsArgumentError,
    );
    expect(
      () => flexible(FieldKind.choice, options: {'id1': 'workshop'}),
      throwsArgumentError,
    );
    final field = flexible(
      FieldKind.choice,
      options: {'id1': 'Evening session'},
    );
    expect(
      LayoutField.fromJson(field.toJson()).addedOptions,
      field.addedOptions,
    );
  });

  test('NMC selections stay closed to user-entered options', () {
    for (final field in nursingPilot.fields.where(
      (field) =>
          field.definition.kind == FieldKind.choice ||
          field.definition.kind == FieldKind.multipleChoices,
    )) {
      final custom = storeChoiceSelection((
        id: null,
        text: 'Unreviewed option',
      ));
      final value = field.definition.kind == FieldKind.choice
          ? custom
          : [custom];
      expect(field.definition.allowCustomOptions, isFalse);
      expect(() => field.definition.validate(value), throwsArgumentError);
      expect(
        () => field.reidentify(field.id, addedOptions: {'extra': 'New option'}),
        throwsArgumentError,
      );
    }
  });

  testWidgets('single select adds an option once within its dropdown', (
    tester,
  ) async {
    final field = flexible(FieldKind.choice);
    Object? value;
    bool? saved;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) => RecordingFieldTile(
            field: field,
            value: value,
            onChanged: (next) => setState(() => value = next),
            canSaveOption: true,
            onCustomOption: (label, save) => setState(() {
              saved = save;
              value = storeChoiceSelection((id: null, text: label));
            }),
          ),
        ),
      ),
    );
    expect(find.text('Single choice'), findsOneWidget);
    await tester.tap(find.text('Single choice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add new option').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Evening   session ');
    await tester.tap(find.text('Use once'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.text('Evening session'), findsOneWidget);
    expect(field.addedOptions, isEmpty);
  });

  testWidgets('multi select rejects a duplicate and stages a reusable option', (
    tester,
  ) async {
    final field = flexible(
      FieldKind.multipleChoices,
      options: {'saved': 'Evening session'},
    );
    (String, bool)? action;
    await tester.pumpWidget(
      app(
        RecordingFieldTile(
          field: field,
          value: ['base'],
          onChanged: (_) {},
          canSaveOption: true,
          onCustomOption: (label, save) => action = (label, save),
        ),
      ),
    );
    await tester.tap(find.text('Add new option'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' evening\t SESSION ');
    await tester.tap(find.text('Save as option'));
    await tester.pumpAndSettle();
    expect(action, isNull);
    expect(find.text('This option already exists.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Self study');
    await tester.tap(find.text('Save as option'));
    await tester.pumpAndSettle();
    expect(action, ('Self study', true));
  });
}
