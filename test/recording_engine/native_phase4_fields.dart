import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/record_export.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'cpd_form_fixture.dart';
import 'equipment_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking Phase 4 storage'))),
    ),
  );
  final scratch = await Directory.systemTemp.createTemp('cpd_phase4_checks_');
  try {
    await _verifyFields(scratch);
    await _verifyUpgrade(p.join(scratch.path, 'legacy.sqlite'));
    debugPrintSynchronously(
      'PHASE4_NATIVE_PASS: field lifecycle and schema 3 upgrade',
    );
  } catch (error, stack) {
    debugPrintSynchronously('PHASE4_NATIVE_FAIL: $error\n$stack');
    rethrow;
  } finally {
    await scratch.delete(recursive: true);
  }
}

Future<void> _verifyFields(Directory scratch) async {
  final path = p.join(scratch.path, 'fields.sqlite');
  var database = await SqliteRecordingRepository.open(path);
  try {
    final equipment = measuredEquipmentTemplate(1);
    final newerEquipment = measuredEquipmentTemplate(2);
    final free = cpdFormTemplate();
    await database.saveTemplate(equipment);
    await database.saveTemplate(newerEquipment);
    await database.saveTemplate(free, maxActiveFields: cpdActiveFieldLimit);
    final collection = await database.createCollection('Workshop');
    final independent = await database.createCollection('Depot');
    final layout = await database.applyTemplate(
      collection.id,
      equipment,
      expectedVersion: 1,
    );
    final other = await database.applyTemplate(
      independent.id,
      equipment,
      expectedVersion: 1,
    );
    _check(
      layout.fields.first.id != other.fields.first.id,
      'isolated template adoption',
    );
    _check(
      layout.headings.first.beforeFieldId == layout.fields.first.id,
      'rebound heading',
    );
    final fields = {
      for (final (index, field) in equipment.fields.indexed)
        field.id: layout.fields[index],
    };
    final result = fields['result']!;
    final pressure = fields['pressure']!;
    final lockout = fields['lockout']!;
    final evidence = fields['evidence']!;
    final stored = await File(
      p.join(scratch.path, 'service-evidence.txt'),
    ).writeAsString('original');
    final originals = ManagedAttachmentFiles(scratch);
    final attachment = await originals.copyOriginal(stored);
    final identity = fields['asset']!.id;
    await _rejects<ArgumentError>(
      () => database.createRecord(collection.id, {
        identity: 'P-460',
        result.id: 'monitor',
        pressure.id: 40.1,
      }, expectedLayoutVersion: 2),
    );
    final record = await database.createRecord(
      collection.id,
      {
        identity: 'P-460',
        result.id: 'monitor',
        pressure.id: '40.10',
        lockout.id: false,
        evidence.id: [attachment.id],
      },
      expectedLayoutVersion: 2,
      newAttachments: [attachment],
    );
    final pressureV2 = newerEquipment.fields.singleWhere(
      (f) => f.id == 'pressure',
    );
    await _rejects<ArgumentError>(
      () => database.reviseLayout(
        collection.id,
        [pressureV2.reidentify(pressure.id)],
        headings: [],
        expectedVersion: 2,
      ),
    );
    final draft = LayoutDraft(layout);
    final updatedResult = newerEquipment.fields.singleWhere(
      (f) => f.id == 'result',
    );
    draft.configure(updatedResult.reidentify(result.id));
    draft.configure(
      LayoutField(
        id: lockout.id,
        definition: lockout.definition,
        labelOverride: 'Isolation confirmed',
        required: true,
        defaultValue: false,
      ),
    );
    draft.move(lockout.id, 0);
    draft.retire(pressure.id);
    draft.retire(evidence.id);
    draft.add(pressureV2.reidentify('pressure-kpa'));
    final notes = fields['notes']!;
    draft.add(
      LayoutField(
        id: 'inspector',
        definition: notes.definition,
        labelOverride: 'Inspector',
      ),
      applyToExisting: true,
    );
    draft.add(
      LayoutField(
        id: 'order',
        definition: notes.definition,
        labelOverride: 'Work order',
      ),
    );
    final revised = await database.saveLayoutDraft(draft);
    await _rejects<StateError>(() => database.saveLayoutDraft(draft));
    _check(
      revised.fields.first.id == lockout.id &&
          revised.fields.first.format == FieldFormat.standard,
      'changed order, presentation and requirement',
    );
    final edited = await database.updateValues(record.id, {
      result.id: 'monitor',
      'inspector': 'A. Tester',
    }, expectedVersion: 1);
    _check(
      edited.values[pressure.id] == '40.10',
      'retired decimal retained exactly',
    );
    await _rejects<ArgumentError>(
      () => database.updateValues(record.id, {
        'order': 'future only',
      }, expectedVersion: 2),
    );
    await _rejects<ArgumentError>(
      () => database.createRecord(collection.id, {
        identity: 'P-461',
        result.id: 'monitor',
        lockout.id: false,
      }, expectedLayoutVersion: 3),
    );
    await _rejects<ArgumentError>(
      () => database.createRecord(collection.id, {
        identity: 'P-461',
        result.id: 'pass',
      }, expectedLayoutVersion: 3),
    );
    final next = await database.createRecord(collection.id, {
      identity: 'P-461',
      result.id: 'pass',
      ...initialFieldValues(revised.fields),
    }, expectedLayoutVersion: 3);
    _check(next.values[lockout.id] == false, 'explicit new record defaults');
    final latest = await database.applyTemplate(
      collection.id,
      newerEquipment,
      expectedVersion: 3,
    );
    _check(
      latest.templateVersion == 2 && latest.version == 4,
      'new recipe version',
    );
    final cpd = await database.createCollection(
      'Practice',
      fields: free.fields,
      maxActiveFields: cpdActiveFieldLimit,
    );
    final addCpd = LayoutDraft(
      (await database.loadLayouts(cpd.id)).single,
      maxActiveFields: cpdActiveFieldLimit,
    );
    addCpd.add(
      cpdFieldLibrary.search('learning goal').single.instantiate('goal'),
    );
    await database.saveLayoutDraft(addCpd);
    await database.close();
    database = await SqliteRecordingRepository.open(path);
    final historic = (await database.loadRecord(record.id))!;
    final versions = await database.loadLayouts(collection.id);
    final historicalFields = resolveFields(historic.layoutVersion, versions);
    _check(historic.matches('monitor', historicalFields), 'historical search');
    _check(
      !historic.matches('ready to use', historicalFields),
      'no option reinterpretation',
    );
    final rows = recordExportRows(historic, historicalFields);
    _check(
      rows.singleWhere((row) => row[3] == pressure.id)[6] == 'bar',
      'historic unit in export',
    );
    _check(
      rows.singleWhere((row) => row[3] == result.id).last == 'Monitor',
      'historic approval label',
    );
    final evidenceIds = historic.values[evidence.id] as List;
    final storedEvidence = (await database.loadAttachment(
      evidenceIds.single as String,
    ))!;
    _check(
      await (await originals.resolveOriginal(storedEvidence))?.readAsString() ==
          'original',
      'historic original bytes',
    );
    _check(
      versions[1].headings.length == 2 && versions.last.headings.length == 2,
      'heading snapshots survive reopen',
    );
    final stock = (await database.loadTemplate(free.id, 1))!;
    _check(
      stock.origin == TemplateOrigin.bundled &&
          stock.localizedLabel('fr-FR') != stock.label,
      'bundled template metadata round trips',
    );
    final library = (await database.loadLayouts(cpd.id)).last.fields.last;
    _check(
      library.source?.id == 'learning.objective' &&
          library.source?.version == 1,
      'library provenance survives reopen',
    );
  } finally {
    await database.close();
  }
}

Future<void> _verifyUpgrade(String path) async {
  final template = equipmentTemplate(1);
  final field = template.fields.first;
  final payload = jsonEncode([field.toJson()]);
  // Genuine predecessor columns: neither table has the Phase 4 settings column.
  final old = await openDatabase(
    path,
    version: 3,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE templates (id TEXT, version INTEGER, label TEXT, fields TEXT, PRIMARY KEY (id, version))',
      );
      await db.execute(
        'CREATE TABLE layouts (collection_id TEXT, version INTEGER, fields TEXT, include_existing TEXT, template_id TEXT, template_version INTEGER, PRIMARY KEY (collection_id, version))',
      );
      await db.insert('templates', {
        'id': template.id,
        'version': 1,
        'label': template.label,
        'fields': payload,
      });
      await db.insert('layouts', {
        'collection_id': 'legacy',
        'version': 1,
        'fields': payload,
        'include_existing': '[]',
        'template_id': template.id,
        'template_version': 1,
      });
    },
  );
  await old.close();
  final upgraded = await SqliteRecordingRepository.open(path);
  try {
    final layout = (await upgraded.loadLayouts('legacy')).single;
    final recipe = (await upgraded.loadTemplate(template.id, 1))!;
    _check(
      layout.fields.single.definition.toJson().toString() ==
          field.definition.toJson().toString(),
      'legacy definition preserved',
    );
    _check(
      layout.headings.isEmpty &&
          recipe.origin == TemplateOrigin.user &&
          recipe.fields.single.id == field.id,
      'legacy metadata defaults',
    );
  } finally {
    await upgraded.close();
  }
}

void _check(bool condition, String context) {
  if (!condition) throw StateError(context);
}

Future<void> _rejects<T extends Object>(
  Future<Object?> Function() operation,
) async {
  try {
    await operation();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T');
}
