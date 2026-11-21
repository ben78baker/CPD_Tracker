import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/template_review.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cpd_form_fixture.dart';
import 'phase5_fixtures.dart';

void main() {
  test('a retrospective required field stays optional in existing records', () {
    final field = LayoutField(
      id: 'new',
      definition: FieldDefinition(
        id: 'new',
        version: 1,
        label: 'Notes',
        kind: FieldKind.text,
      ),
      required: true,
      defaultValue: 'New only',
    );
    final earlier = LayoutRevision(collectionId: 'c', version: 1, fields: []);
    final later = LayoutRevision(
      collectionId: 'c',
      version: 2,
      fields: [field],
      includeExisting: ['new'],
    );
    expect(resolveFields(1, [earlier, later]).single.required, isFalse);
    expect(resolveFields(2, [earlier, later]).single.required, isTrue);
  });

  test('replacement keeps position and heading and works even at the cap', () {
    final fixture = cpdFormTemplate();
    final first = fixture.fields.first;
    final draft = LayoutDraft(
      LayoutRevision(
        collectionId: 'c',
        version: 1,
        fields: fixture.fields,
        headings: [SectionHeading('h', 'Heading', beforeFieldId: first.id)],
      ),
      maxActiveFields: fixture.fields.length,
    );
    expect(
      () => draft.replace(first.id, fixture.fields.last),
      throwsArgumentError,
    );
    expect(draft.fields.first, same(first));
    draft.replace(first.id, first.reidentify('replacement'));
    expect(draft.fields.first.id, 'replacement');
    expect(draft.headings.single.beforeFieldId, 'replacement');
    expect(draft.activeFieldCount, fixture.fields.length);
  });

  test(
    'CPD bindings allow presentation and priority changes while protecting free workflows',
    () {
      final fields = cpdFormTemplate().fields;
      final first = fields.first;
      final edited = LayoutField(
        id: first.id,
        definition: first.definition,
        required: first.required,
        labelOverride: 'When I did it',
        helpText: 'Day of activity',
      );
      checkCpdLayoutEdit(fields, [...fields.skip(1), edited]);
      expect(
        () => checkCpdLayoutEdit(fields, fields.skip(1).toList()),
        throwsStateError,
      );
      expect(
        () => checkCpdLayoutEdit(fields, [
          first.reidentify('lookalike'),
          ...fields.skip(1),
        ]),
        throwsArgumentError,
      );
      expect(
        () => checkCpdLayoutEdit(fields, [
          first.reidentify(first.id, required: !first.required),
          ...fields.skip(1),
        ]),
        throwsArgumentError,
      );
    },
  );

  test(
    'template diff distinguishes official updates from installed customisations',
    () {
      final original = nursingPreviewTemplate(1);
      final update = nursingPreviewTemplate(2);
      final local = [
        for (final field in original.fields)
          field.reidentify('local-${field.id}'),
      ];
      final adoption = LayoutRevision(
        collectionId: 'c',
        version: 2,
        fields: local,
        templateId: original.id,
        templateVersion: 1,
      );
      final first = local.first;
      final renamed = LayoutField(
        id: first.id,
        definition: first.definition,
        required: first.required,
        labelOverride: 'When it happened',
      );
      final installed = LayoutRevision(
        collectionId: 'c',
        version: 3,
        fields: [
          ...local.skip(2),
          renamed,
          local[1].reidentify('local-extension'),
        ],
        templateId: original.id,
        templateVersion: 1,
      );
      final diff = TemplateReview.compare(
        original: original,
        adoption: adoption,
        installed: installed,
        update: update,
      );
      expect(diff.added, ['learning.objective']);
      expect(diff.localFields, ['local-extension']);
      expect(diff.modifiedLocally, [original.fields.first.id]);
      expect(diff.removedLocally, [original.fields[1].id]);
      expect(diff.localReordered, isTrue);
      expect(diff.publisherReordered, isFalse);
      expect(
        () => TemplateReview.compare(
          original: original,
          adoption: installed,
          installed: installed,
          update: update,
        ),
        throwsArgumentError,
      );
      expect(installed.templateVersion, 1);
      expect(installed.fields.last.id, 'local-extension');
    },
  );

  test(
    'authoring fixture is deterministic and keeps order, metadata and choice IDs',
    () async {
      final recipe = nursingPreviewTemplate(1);
      final encoded = encodeTemplateDefinition(recipe, maximumFields: 20);
      final decoded = decodeTemplateDefinition(encoded, maximumFields: 20);
      expect(encodeTemplateDefinition(decoded), encoded);
      expect(decoded.fields.map((f) => f.id), recipe.fields.map((f) => f.id));
      expect(
        decoded.fields
            .singleWhere((f) => f.id == 'standards.nmc_code')
            .definition
            .choices
            .keys,
        ['people', 'effective', 'safety', 'trust'],
      );
      expect(decoded.localizedLabel('fr-FR'), recipe.localizedLabel('fr'));
      expect(decoded.headings.single.beforeFieldId, recipe.fields.first.id);
      expect(
        () => decodeTemplateDefinition(encoded, maximumFields: 2),
        throwsArgumentError,
      );
      expect(
        () => decodeTemplateDefinition(
          encoded.replaceFirst('"formatVersion": 1', '"formatVersion": 2'),
        ),
        throwsFormatException,
      );
      final pdf = await nursingExamplePdf(
        recipe,
        nursingCompletedExample(recipe),
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    },
  );
}
