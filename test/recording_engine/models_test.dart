import 'dart:convert';

import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'equipment_fixture.dart';

void main() {
  test('equipment recipe supports eight generic reusable fields', () {
    final fixture = equipmentTemplate(1);
    expect(fixture.fields, hasLength(8));
    final next = fixture.fields.singleWhere((field) => field.id == 'next');
    next.definition.validate('2099-01-01');
    expect(() => next.definition.validate('2025-02-29'), throwsArgumentError);
    expect(() => next.definition.validate('2024-02-29\n'), throwsArgumentError);
    next.definition.validate('2024-02-29');
    final raw = jsonEncode(fixture.fields.last.toJson());
    expect(jsonEncode(LayoutField.fromJson(jsonDecode(raw)).toJson()), raw);
  });

  test(
    'historical choice, label, order and applicability survive revision',
    () {
      final older = equipmentTemplate(1);
      final newer = equipmentTemplate(2);
      final oldResult = older.fields.singleWhere(
        (field) => field.id == 'result',
      );
      final original = LayoutRevision(
        collectionId: 'workshop',
        version: 1,
        fields: older.fields,
      );
      final retrospective = LayoutField(
        id: 'verifier',
        definition: older.fields[1].definition,
        labelOverride: 'Verified by',
        helpText: 'Who signed off this service?',
      );
      final later = LayoutRevision(
        collectionId: 'workshop',
        version: 2,
        fields: [
          ...newer.fields.reversed.where((field) => field.id != 'evidence'),
          retrospective,
        ],
        includeExisting: ['verifier'],
      );

      final projected = resolveFields(1, [original, later]);
      expect(projected.map((field) => field.id), [
        ...older.fields.map((field) => field.id),
        'verifier',
      ]);
      expect(
        projected.singleWhere((field) => field.id == 'result'),
        same(oldResult),
      );
      final record = RecordingRecord(
        id: 'record',
        collectionId: 'workshop',
        layoutVersion: 1,
        version: 1,
        deleted: false,
        values: {
          'asset': 'M-17',
          'result': 'monitor',
          'evidence': ['photo', 'report'],
        },
      );
      expect(record.matches('monitor', projected), isTrue);
      expect(record.project(projected), [
        'M-17',
        null,
        null,
        null,
        null,
        null,
        'Monitor',
        ['photo', 'report'],
        null,
      ]);
      expect(resolveFields(2, [original, later]), later.fields);
    },
  );

  test(
    'definition validation distinguishes choices and rejects duplicate IDs',
    () {
      final definition = FieldDefinition(
        id: 'categories',
        version: 1,
        label: 'Service categories',
        kind: FieldKind.multipleChoices,
        choices: {'oil': 'Oil change', 'inspection': 'Safety inspection'},
      );
      expect(definition.displayValue(['inspection', 'oil']), [
        'Safety inspection',
        'Oil change',
      ]);
      expect(() => definition.validate(['oil', 'oil']), throwsArgumentError);
      expect(() => definition.validate(['unknown']), throwsArgumentError);
      final field = LayoutField(id: 'field', definition: definition);
      expect(
        () => LayoutRevision(
          collectionId: 'id',
          version: 1,
          fields: [field, field],
        ),
        throwsArgumentError,
      );
    },
  );

  test('record snapshots are detached from mutable input lists', () {
    final links = ['one', 'two'];
    final record = RecordingRecord(
      id: 'id',
      collectionId: 'group',
      version: 1,
      layoutVersion: 1,
      deleted: false,
      values: {'evidence': links},
    );
    links.clear();
    expect(record.values['evidence'], ['one', 'two']);
    expect(
      () => (record.values['evidence'] as List).clear(),
      throwsUnsupportedError,
    );
  });

  test('managed attachment metadata rejects absolute and traversal paths', () {
    for (final locator in [
      '/tmp/proof.jpg',
      'a/../proof.jpg',
      r'a\proof.jpg',
      'a//proof.jpg',
    ]) {
      expect(
        () => RecordingAttachment(
          id: 'asset',
          kind: AttachmentKind.managed,
          locator: locator,
          name: 'Proof',
        ),
        throwsArgumentError,
      );
    }
  });
}
