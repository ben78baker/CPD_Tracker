import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/template_review.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _baseline = LayoutRevision(
  collectionId: 'practice',
  version: 1,
  fields: nursingPilot.fields,
);
LayoutDraft _draft() => LayoutDraft(_baseline, maxActiveFields: 20);
final _optional = nursingPilot.fields.singleWhere(
  (f) => f.definition.id == 'nmc.practice',
);
final _method = nursingPilot.fields.singleWhere(
  (f) => f.definition.id == 'nmc.method',
);

void main() {
  test('free, app-wide, legacy, template and combined grant scopes', () {
    final free = CreationAccess();
    final scoped = CreationAccess(templates: [nursingPilot.id]);
    final wide = CreationAccess(customFields: true);
    final legacy = CreationAccess(legacy: true);
    final combined = CreationAccess(
      customFields: true,
      templates: [nursingPilot.id],
    );
    for (final access in [free, scoped, wide, legacy, combined]) {
      expect(access.allows(ProfessionKind.standard, null), isTrue);
    }
    expect(free.allows(ProfessionKind.custom, null), isFalse);
    expect(scoped.allows(ProfessionKind.custom, nursingPilot.id), isFalse);
    expect(scoped.allows(ProfessionKind.template, nursingPilot.id), isTrue);
    expect(scoped.allows(ProfessionKind.template, 'another'), isFalse);
    expect(wide.allows(ProfessionKind.template, nursingPilot.id), isFalse);
    expect(legacy.allows(ProfessionKind.custom, null), isTrue);
    expect(combined.allows(ProfessionKind.custom, null), isTrue);
    expect(combined.allows(ProfessionKind.template, nursingPilot.id), isTrue);
  });

  test(
    'scoped changes allow arrangement and independent optional report inclusion',
    () {
      final draft = _draft()..move(_optional.id, 0);
      final exclusion = ReportSelection(excluded: [_optional.id]);
      checkTemplateArrangement(_baseline, draft, exclusion, nursingReportRules);
      expect(draft.fields.first.id, _optional.id);
      expect(
        nursingReportRules.assess(_baseline, draft, exclusion).optionalChanges,
        isTrue,
      );
      draft.retire(_optional.id);
      checkTemplateArrangement(
        _baseline,
        draft,
        ReportSelection(),
        nursingReportRules,
      );
      draft.reinstate(_optional);
      expect(
        nursingReportRules
            .assess(_baseline, draft, ReportSelection())
            .optionalChanges,
        isFalse,
      );
    },
  );

  test(
    'scoped services reject injected field, rename, changed options and required hide',
    () {
      final added = _draft()..add(_optional.reidentify('new-id'));
      expect(
        () => checkTemplateArrangement(
          _baseline,
          added,
          ReportSelection(),
          nursingReportRules,
        ),
        throwsStateError,
      );
      final renamed = _draft()
        ..configure(
          LayoutField(
            id: _optional.id,
            definition: _optional.definition,
            helpText: 'Changed settings',
          ),
        );
      expect(
        () => checkTemplateArrangement(
          _baseline,
          renamed,
          ReportSelection(),
          nursingReportRules,
        ),
        throwsStateError,
      );
      final altered = _draft()
        ..configure(
          LayoutField(
            id: _method.id,
            required: true,
            definition: FieldDefinition(
              id: _method.definition.id,
              version: 2,
              label: _method.label,
              kind: FieldKind.choice,
              choices: {
                ..._method.definition.choices,
                'other': 'Changed meaning',
              },
            ),
          ),
        );
      expect(
        () => checkTemplateArrangement(
          _baseline,
          altered,
          ReportSelection(),
          nursingReportRules,
        ),
        throwsStateError,
      );
      expect(
        nursingReportRules
            .assess(_baseline, altered, ReportSelection())
            .incomplete,
        isTrue,
      );
      expect(
        () => checkTemplateArrangement(
          _baseline,
          _draft(),
          ReportSelection(excluded: [_method.id]),
          nursingReportRules,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'draft persistence preserves state without altering layout and report snapshots',
    () {
      final layout = _draft()
        ..retire(_optional.id)
        ..reinstate(_optional);
      final draft = ProfessionDraft(
        id: 'draft',
        kind: ProfessionKind.template,
        layout: layout,
        report: ReportSelection(excluded: [_optional.id]),
        templateId: nursingPilot.id,
        templateVersion: 1,
        name: 'Practice',
      );
      final serialised = jsonEncode(draft.toJson());
      final restored = ProfessionDraft.fromJson(
        jsonDecode(serialised) as Map<String, dynamic>,
      );
      expect(jsonEncode(restored.toJson()), serialised);
      expect(restored.layout.reinstated, {_optional.id});
      expect(restored.report.excluded, {_optional.id});
      expect(
        _baseline.fields.indexOf(_optional),
        isNot(_baseline.fields.length - 1),
      );
    },
  );

  test('pilot definition round-trips and generates the example PDF', () async {
    final definition = encodeTemplateDefinition(
      nursingPilot,
      maximumFields: 20,
    );
    final decoded = decodeTemplateDefinition(definition, maximumFields: 20);
    expect(encodeTemplateDefinition(decoded), definition);
    final examples = nursingExamples(decoded);
    expect(examples, hasLength(3));
    for (final example in examples) {
      for (final value in example.values.entries) {
        decoded.fields
            .singleWhere((field) => field.id == value.key)
            .definition
            .validate(value.value);
      }
    }
    final pdf = await nursingSampleReport(decoded, ReportSelection());
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    const output = String.fromEnvironment('PHASE6_ARTIFACTS');
    if (output.isNotEmpty) {
      await Directory(output).create(recursive: true);
      await File(p.join(output, 'nursing_activity_log.pdf')).writeAsBytes(pdf);
      await File(
        p.join(output, 'nursing_template_v1.json'),
      ).writeAsString(definition);
      final sampleJson = const JsonEncoder.withIndent('  ').convert([
        for (final example in examples)
          {'label': example.label, 'values': example.values},
      ]);
      await File(
        p.join(output, 'nursing_examples.json'),
      ).writeAsString('$sampleJson\n');
    }
  });
}
