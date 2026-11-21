import 'dart:convert';

import 'package:cpd_tracker/recording_engine/field_library.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/record_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cpd_form_fixture.dart';
import 'equipment_fixture.dart';

void main() {
  test(
    'exact decimals, integers, Booleans, URLs and bounded text round-trip',
    () {
      final definitions = measuredEquipmentTemplate(
        1,
      ).fields.map((f) => f.definition);
      final samples = <String, (Object, List<Object>)>{
        'equipment.pressure': (
          '40.10',
          [40.1, '04', '2e3', '40.100', '-0.1', '1,25', '3\n'],
        ),
        'cycle': (0, [2.5, '2', false]),
        'equipment.lockout': (false, ['false', 0]),
        'manual': (
          'https://example.com/manual.pdf',
          [
            'javascript:void(0)',
            'https://',
            'ftp://example.com',
            'https://example.com/a b',
          ],
        ),
      };
      for (final item in definitions.where(
        (field) => samples.containsKey(field.id),
      )) {
        final (valid, invalid) = samples[item.id]!;
        final decoded = FieldDefinition.fromJson(
          jsonDecode(jsonEncode(item.toJson())),
        );
        expect(decoded.toJson(), item.toJson());
        decoded.validate(valid);
        for (final value in invalid) {
          expect(
            () => decoded.validate(value),
            throwsArgumentError,
            reason: '${item.id}: $value',
          );
        }
      }
      final description = FieldDefinition(
        id: 'description',
        version: 1,
        label: 'Description',
        kind: FieldKind.text,
        maxLength: 2,
      );
      description.validate('é🌱');
      expect(() => description.validate('abc'), throwsArgumentError);
    },
  );

  test(
    'presentation formats and defaults remain independent of data identity',
    () {
      final equipment = measuredEquipmentTemplate(1);
      final checkbox = equipment.fields.singleWhere((f) => f.id == 'lockout');
      final field = LayoutField(
        id: checkbox.id,
        definition: checkbox.definition,
        required: true,
        labelOverride: 'Safety lock checked',
        defaultValue: false,
      );
      final decoded = LayoutField.fromJson(
        jsonDecode(jsonEncode(field.toJson())),
      );
      expect(decoded.toJson(), field.toJson());
      expect(initialFieldValues([decoded]), {checkbox.id: false});
      expect(decoded.format, FieldFormat.standard);
      expect(checkbox.format, FieldFormat.checkbox);
      expect(
        () => LayoutField(
          id: 'mismatch',
          definition: field.definition,
          format: FieldFormat.photograph,
        ),
        throwsArgumentError,
      );
      expect(
        () => LayoutField(
          id: 'attachment',
          definition: equipment.fields.last.definition,
          defaultValue: ['some-user-file'],
        ),
        throwsArgumentError,
      );
    },
  );

  test('draft orders complete fields and caps data fields only', () {
    final fixture = cpdFormTemplate();
    final base = LayoutRevision(
      collectionId: 'cpd',
      version: 1,
      fields: fixture.fields,
    );
    final draft = LayoutDraft(base, maxActiveFields: 6);
    final objective = cpdFieldLibrary
        .search('learning goal')
        .single
        .instantiate('objective');
    draft.add(objective, applyToExisting: true);
    draft.move('objective', 1);
    draft.setHeadings([
      SectionHeading('learning', 'Learning', beforeFieldId: 'objective'),
    ]);
    expect(draft.fields[1], same(objective));
    expect(draft.activeFieldCount, 6);
    expect(draft.includeExisting, {'objective'});
    expect(
      () => draft.add(objective.reidentify('second')),
      throwsArgumentError,
    );
    expect(
      () => draft.setHeadings([
        SectionHeading('bad', 'Bad anchor', beforeFieldId: 'x'),
      ]),
      throwsArgumentError,
    );
    expect(() => draft.move('objective', 6), throwsRangeError);
    draft.retire('objective');
    expect(draft.includeExisting, isEmpty);
    expect(draft.headings, isEmpty);
    expect(base.fields, fixture.fields);
    // The CPD host can use the same centrally supplied cap at save.
    expect(cpdActiveFieldLimit, 20);
  });

  test('unit, precision and type changes require a fresh field instance', () {
    final fixture = measuredEquipmentTemplate(1);
    final pressure = fixture.fields.singleWhere((f) => f.id == 'pressure');
    final draft = LayoutDraft(
      LayoutRevision(
        collectionId: 'workshop',
        version: 1,
        fields: fixture.fields,
      ),
    );
    for (final replacement in [
      (FieldKind.decimal, 'kPa', 2),
      (FieldKind.decimal, 'bar', 1),
      (FieldKind.integer, 'bar', null),
    ]) {
      final (kind, unit, decimals) = replacement;
      final next = LayoutField(
        id: pressure.id,
        definition: FieldDefinition(
          id: pressure.definition.id,
          version: 2,
          label: pressure.label,
          kind: kind,
          unit: unit,
          decimalPlaces: decimals,
        ),
      );
      expect(() => draft.configure(next), throwsArgumentError);
    }
    final newer = measuredEquipmentTemplate(
      2,
    ).fields.singleWhere((f) => f.id == 'pressure');
    draft.retire(pressure.id);
    draft.add(newer.reidentify('pressure-kpa'));
    expect(draft.fields.last.definition.unit, 'kPa');
    expect(pressure.definition.unit, 'bar');
  });

  test(
    'catalogue searches categories, localized text, aliases and scheme scope',
    () {
      expect(cpdFieldLibrary.search(''), hasLength(8));
      expect(
        cpdFieldLibrary
            .search('organisme formation', locale: 'fr-CA')
            .single
            .source
            .id,
        'activity.provider',
      );
      expect(
        cpdFieldLibrary.search('interactive', locale: 'fr').single.source.id,
        'time.participatory_minutes',
      );
      expect(
        cpdFieldLibrary
            .search('certificate', category: 'evidence')
            .single
            .source
            .id,
        'evidence.files',
      );
      expect(cpdFieldLibrary.search('', tag: 'NMC'), hasLength(2));
      expect(cpdFieldLibrary.search('non-matching query'), isEmpty);
      expect(
        cpdFieldLibrary.categoryLabel('time', locale: 'fr'),
        'Durée et crédits',
      );
      expect(
        cpdFieldLibrary.search('participatory').single.prototype.defaultValue,
        isNull,
      );
    },
  );

  test('new library versions retain prior field semantics and provenance', () {
    final first = cpdFieldLibrary.search('learning goal').single;
    final adopted = first.instantiate('goal-1');
    final next = LibraryFieldVersion(
      source: LibrarySource(first.source.id, 2),
      prototype: LayoutField(
        id: first.source.id,
        definition: FieldDefinition(
          id: first.source.id,
          label: 'Course objective',
          kind: FieldKind.text,
          version: 2,
          maxLength: 80,
        ),
      ),
      category: 'reflection',
      description: 'The aim of the course.',
    );
    final updated = FieldLibrary(
      [first, next],
      categories: const {
        'reflection': {'en': 'Reflection'},
      },
    );
    expect(updated.search('objective').single.source.version, 2);
    expect(updated.load(first.source.id, 1), same(first));
    expect(adopted.label, 'Learning objective');
    final decoded = LayoutField.fromJson(
      jsonDecode(jsonEncode(adopted.toJson())),
    );
    expect(decoded.source!.version, 1);
    expect(decoded.definition.multiline, isTrue);
    expect(next.instantiate('goal-2').id, 'goal-2');
  });

  test(
    'exports stable IDs, localised labels, units and historical exact values',
    () {
      final older = measuredEquipmentTemplate(1);
      final record = RecordingRecord(
        id: 'record',
        collectionId: 'workshop',
        layoutVersion: 1,
        version: 1,
        deleted: false,
        values: {'pressure': '40.10', 'result': 'monitor', 'lockout': false},
      );
      final rows = recordExportRows(record, older.fields, locale: 'fr');
      expect(rows[0], [
        'record',
        'workshop',
        '1',
        'pressure',
        'Test pressure',
        'decimal',
        'bar',
        '"40.10"',
        '40.10',
      ]);
      expect(rows[1].last, 'Monitor');
      expect(rows[2].last, 'false');
      expect(record.matches('monitor', older.fields), isTrue);
      expect(record.matches('ready to use', older.fields), isFalse);
    },
  );
}
