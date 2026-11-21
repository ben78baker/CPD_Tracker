import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/record_export.dart';
import 'package:cpd_tracker/recording_engine/template_review.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'equipment_fixture.dart';
import 'phase5_fixtures.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Verifying layout history'))),
    ),
  );
  final scratch = await Directory.systemTemp.createTemp('phase5_native_');
  try {
    await verifyPhase5(p.join(scratch.path, 'records.sqlite'));
    debugPrintSynchronously(
      'PHASE5_NATIVE_PASS: layouts, records, history, exports and reopened store',
    );
  } catch (error, trace) {
    debugPrintSynchronously('PHASE5_NATIVE_FAIL: $error\n$trace');
    rethrow;
  } finally {
    await scratch.delete(recursive: true);
  }
}

Future<void> verifyPhase5(String path) async {
  var database = await SqliteRecordingRepository.open(path);
  try {
    final workshop = await database.createCollection('Workshop');
    final original = measuredEquipmentTemplate(1);
    await database.saveTemplate(original);
    final adopted = await database.applyTemplate(
      workshop.id,
      original,
      expectedVersion: 1,
    );
    final fields = {
      for (final (index, field) in original.fields.indexed)
        field.id: adopted.fields[index],
    };
    final asset = fields['asset']!;
    final pressure = fields['pressure']!;
    final notes = fields['notes']!;
    final status = fields['result']!;
    final old = await database.createRecord(workshop.id, {
      asset.id: 'P-460',
      pressure.id: '4.20',
      status.id: 'monitor',
      notes.id: 'Original finding',
    }, expectedLayoutVersion: 2);
    final draft = LayoutDraft(adopted);
    draft.retire(notes.id);
    draft.replace(
      pressure.id,
      LayoutField(
        id: 'new-pressure',
        definition: FieldDefinition(
          id: 'new-pressure',
          version: 1,
          label: pressure.label,
          kind: FieldKind.decimal,
          unit: 'kPa',
          decimalPlaces: 1,
        ),
      ),
    );
    final update = measuredEquipmentTemplate(2);
    final updatedStatus = update.fields.singleWhere((f) => f.id == 'result');
    draft.configure(updatedStatus.reidentify(status.id));
    draft.configure(
      LayoutField(
        id: asset.id,
        definition: asset.definition,
        required: asset.required,
        labelOverride: 'Asset reference',
      ),
    );
    draft.add(
      LayoutField(
        id: 'remarks',
        definition: notes.definition,
        required: true,
        labelOverride: 'Review comments',
      ),
      applyToExisting: true,
    );
    draft.add(asset.reidentify('asset-duplicate'));
    draft.move('asset-duplicate', 1);
    final installed = await database.saveLayoutDraft(draft);
    await database.saveTemplate(update);
    final diff = TemplateReview.compare(
      original: original,
      adoption: adopted,
      installed: installed,
      update: update,
    );
    _verify(
      diff.changed.contains('pressure') && diff.changed.contains('result'),
      'publisher changes',
    );
    _verify(
      diff.localFields.contains('asset-duplicate') &&
          diff.removedLocally.contains('notes'),
      'local changes',
    );
    _verify(installed.templateVersion == 1, 'update does not activate itself');
    await database.updateValues(old.id, {
      'remarks': 'Historical comment',
    }, expectedVersion: 1);
    await database.updateValues(old.id, {'remarks': null}, expectedVersion: 2);
    final current = await database.createRecord(workshop.id, {
      asset.id: 'P-461',
      'asset-duplicate': 'spare',
      status.id: 'pass',
      'new-pressure': '420.0',
      'remarks': 'Checked',
    }, expectedLayoutVersion: 3);
    await database.updateValues(current.id, {
      'remarks': 'Reviewed',
    }, expectedVersion: 1);

    final nursing = nursingPreviewTemplate(1);
    final collection = await database.createCollection('Nursing');
    await database.saveTemplate(nursing);
    final nmc = await database.applyTemplate(
      collection.id,
      nursing,
      expectedVersion: 1,
      maxActiveFields: cpdActiveFieldLimit,
    );
    final cpdDraft = LayoutDraft(nmc, maxActiveFields: cpdActiveFieldLimit);
    cpdDraft.move(nmc.fields.first.id, 2);
    cpdDraft.add(
      phase5Library
          .load('learning.objective', 1)!
          .instantiate('learning-instance'),
    );
    checkCpdLayoutEdit(nmc.fields, cpdDraft.fields);
    await database.saveLayoutDraft(cpdDraft);

    await database.close();
    database = await SqliteRecordingRepository.open(path);
    final historic = (await database.loadRecord(old.id))!;
    final layouts = await database.loadLayouts(workshop.id);
    final historicFields = resolveFields(historic.layoutVersion, layouts);
    final rows = recordExportRows(historic, historicFields);
    _verify(
      rows.singleWhere((r) => r[3] == pressure.id)[6] == 'bar',
      'old unit in export',
    );
    _verify(
      rows.singleWhere((r) => r[3] == pressure.id).last == '4.20',
      'old exact value',
    );
    _verify(
      rows.singleWhere((r) => r[3] == notes.id).last == 'Original finding',
      'retired values',
    );
    _verify(
      historic.matches('monitor', historicFields),
      'retired selection resolves',
    );
    _verify(
      rows.singleWhere((r) => r[3] == asset.id)[4] == 'Equipment ID',
      'label from creation',
    );
    _verify(
      !historic.values.containsKey('remarks'),
      'historical required field can be cleared',
    );
    final reopened = (await database.loadRecord(current.id))!;
    _verify(
      reopened.values['remarks'] == 'Reviewed' &&
          reopened.values['asset-duplicate'] == 'spare',
      'saved edits and duplicate after reopen',
    );
    _verify(
      (await database.loadLayouts(collection.id)).last.fields.last.source?.id ==
          'learning.objective',
      'nursing custom layout after reopen',
    );
  } finally {
    await database.close();
  }
}

void _verify(bool condition, String description) {
  if (!condition) throw StateError(description);
}
