import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/recording_engine/import_plan.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'equipment_fixture.dart';

/// Device entry point for a disposable Flutter app containing only sqflite,
/// uuid, path and the recording modules. Run as a Flutter target, away from
/// an installed CPD Tracker app or its Documents directory.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Running recording engine checks')),
    ),
  );
  final scratch = await Directory.systemTemp.createTemp('recording_smoke_');
  try {
    final sqlite = await databaseFactory.openDatabase(
      p.join(scratch.path, 'version.sqlite'),
    );
    final version = await sqlite.rawQuery('SELECT sqlite_version()');
    await sqlite.close();
    await _equipment(scratch);
    await _transactionRetry(scratch);
    await _migration(scratch);
    await _blockedMigration(scratch);
    debugPrintSynchronously(
      'RECORDING_SMOKE_PASS: 4 scenarios; SQLite ${version.single.values.single}',
    );
  } catch (error, stack) {
    debugPrintSynchronously('RECORDING_SMOKE_FAIL: $error\n$stack');
    rethrow;
  } finally {
    await scratch.delete(recursive: true);
  }
}

Future<void> _equipment(Directory scratch) async {
  final path = p.join(scratch.path, 'equipment.sqlite');
  var db = await SqliteRecordingRepository.open(path);
  try {
    final first = await db.createCollection('Workshop');
    final second = await db.createCollection('Depot');
    final recipe = equipmentTemplate(1);
    await db.saveTemplate(recipe);
    await _rejects<ArgumentError>(
      () => db.applyTemplate(
        first.id,
        recipe,
        expectedVersion: 1,
        maxActiveFields: 7,
      ),
    );
    final one = await db.applyTemplate(first.id, recipe, expectedVersion: 1);
    final two = await db.applyTemplate(second.id, recipe, expectedVersion: 1);
    _check(
      one.fields
          .map((f) => f.id)
          .toSet()
          .intersection(two.fields.map((f) => f.id).toSet())
          .isEmpty,
      'independent instance IDs',
    );
    final [asset, technician, _, next, _, notes, result, evidence] = one.fields;
    final photoFile = await File(
      p.join(scratch.path, 'synthetic.jpg'),
    ).writeAsBytes([1, 2, 3]);
    final files = ManagedAttachmentFiles(scratch);
    final photo = await files.copyOriginal(photoFile);
    final reference = RecordingAttachment(
      id: 'manual',
      kind: AttachmentKind.link,
      locator: 'https://example.com/equipment-manual',
      name: 'Manual',
    );
    final record = await db.createRecord(
      first.id,
      {
        asset.id: 'M-17',
        technician.id: 'A. Tester',
        next.id: '2099-04-01',
        notes.id: 'First line\nSecond line',
        result.id: 'monitor',
        evidence.id: [photo.id, reference.id, photo.id],
      },
      expectedLayoutVersion: 2,
      newAttachments: [photo, reference],
    );

    final versionTwo = equipmentTemplate(2);
    await db.saveTemplate(versionTwo);
    final laterResult = LayoutField(
      id: result.id,
      definition: versionTwo.fields
          .singleWhere((f) => f.id == 'result')
          .definition,
    );
    final historical = LayoutField(
      id: 'historical',
      definition: notes.definition,
      labelOverride: 'Reviewer',
      placeholder: 'Name',
    );
    final future = LayoutField(
      id: 'future',
      definition: notes.definition,
      labelOverride: 'Work order',
    );
    final revised = await db.reviseLayout(
      first.id,
      [laterResult, next, asset, historical, future],
      expectedVersion: 2,
      includeExisting: [historical.id],
      maxActiveFields: 5,
    );
    _check(
      revised.templateId == recipe.id && revised.templateVersion == 1,
      'customised layout retains original template provenance',
    );
    await _rejects<StateError>(
      () => db.reviseLayout(first.id, [], expectedVersion: 2),
    );
    await _rejects<ArgumentError>(
      () => db.reviseLayout(first.id, [
        ...revised.fields,
        evidence,
      ], expectedVersion: 3),
    );
    await _rejects<ArgumentError>(
      () => db.updateValues(record.id, {future.id: 'WO-1'}, expectedVersion: 1),
    );
    await _rejects<DatabaseException>(
      () => db.updateValues(record.id, {
        notes.id: 'Should roll back',
        evidence.id: ['absent'],
      }, expectedVersion: 1),
    );
    final preserved = (await db.loadRecord(record.id))!;
    _check(
      preserved.version == 1 &&
          preserved.values[notes.id] == 'First line\nSecond line',
      'failed patch rolls back all fields and edit version',
    );
    final history = resolveFields(2, await db.loadLayouts(first.id));
    _check(
      preserved.matches('monitor', history) &&
          preserved.matches('M-17', history) &&
          preserved.project(history).contains('Monitor') &&
          history.last.placeholder == 'Name',
      'historical choice, projection and search',
    );
    final fresh = await db.createRecord(first.id, {
      asset.id: 'M-18',
      result.id: 'pass',
      future.id: 'WO-2',
    }, expectedLayoutVersion: 3);
    _check(
      fresh.matches('Ready to use', revised.fields),
      'new choice vocabulary',
    );
    await db.updateValues(record.id, {
      historical.id: 'Reviewer B',
    }, expectedVersion: 1);
    await db.setRecordDeleted(record.id, true, expectedVersion: 2);
    _check((await db.loadRecords(first.id)).length == 1, 'tombstone filters');
    await db.close();
    db = await SqliteRecordingRepository.open(path);
    await db.setRecordDeleted(record.id, false, expectedVersion: 3);
    final restored = (await db.loadRecord(record.id))!;
    _check(
      jsonEncode(restored.values[evidence.id]) ==
          jsonEncode([photo.id, reference.id, photo.id]),
      'reopen and restore retain ordered duplicate proof links',
    );
    _check(
      restored.values[historical.id] == 'Reviewer B' &&
          restored.values[future.id] == null,
      'retrospective addition remains independent',
    );
    _check(
      await (await files.resolveOriginal(
        (await db.loadAttachment(photo.id))!,
      ))!.readAsBytes().then((bytes) => jsonEncode(bytes) == '[1,2,3]'),
      'managed proof bytes persist',
    );
  } finally {
    await db.close();
  }
}

Future<void> _transactionRetry(Directory scratch) async {
  final path = p.join(scratch.path, 'retry.sqlite');
  var db = await SqliteRecordingRepository.open(path);
  try {
    await db.captureImport('source', '{"synthetic":true}');
    final attachment = RecordingAttachment(
      id: 'proof',
      kind: AttachmentKind.unresolved,
      locator: 'absent',
      name: 'Proof',
    );
    final field = equipmentTemplate(1).fields.last;
    RecordingImportPlan plan(List<RecordingAttachment> attachments) =>
        RecordingImportPlan(
          sourceId: 'source',
          rawSnapshot: '{"synthetic":true}',
          metadata: '{}',
          blocked: false,
          collections: [const RecordingCollection('collection', 'Workshop', 1)],
          layouts: [
            LayoutRevision(
              collectionId: 'collection',
              version: 1,
              fields: [field],
            ),
          ],
          records: [
            RecordingRecord(
              id: 'record',
              collectionId: 'collection',
              layoutVersion: 1,
              version: 1,
              deleted: false,
              values: {
                field.id: ['proof'],
              },
            ),
          ],
          attachments: attachments,
        );
    // This fails after the collection, layout and record inserts.
    await _rejects<DatabaseException>(() => db.stageImport(plan([])));
    await db.close();
    db = await SqliteRecordingRepository.open(path);
    _check(
      (await db.loadImportSnapshot('source'))!.status ==
              ImportStatus.captured &&
          await db.loadCollection('collection') == null &&
          await db.loadRecord('record') == null,
      'interrupted graph leaves snapshot and no partial destination rows',
    );
    _check(
      await db.stageImport(plan([attachment])) == ImportStatus.staged &&
          await db.stageImport(plan([attachment])) == ImportStatus.staged &&
          (await db.loadRecords('collection')).length == 1,
      'retry is idempotent',
    );
    await db.verifyImport(
      plan([attachment]),
      verifyManagedOriginal: (_) async => false,
    );
    _check(
      (await db.loadImportSnapshot('source'))!.status == ImportStatus.verified,
      'unresolved evidence remains explicitly unresolved',
    );
  } finally {
    await db.close();
  }
}

Future<void> _migration(Directory scratch) async {
  final directory = await Directory(
    p.join(scratch.path, 'attachments'),
  ).create();
  final original = await File(
    p.join(directory.path, 'proof.pdf'),
  ).writeAsBytes([7, 0, 3]);
  final orphaned = await File(
    p.join(scratch.path, 'outside.pdf'),
  ).writeAsBytes([4]);
  await Link(p.join(directory.path, 'alias.pdf')).create(orphaned.path);
  final raw = _legacyRow({
    'attachments': [
      'attachments/proof.pdf',
      '/old/container/Documents/attachments/proof.pdf',
      'https://example.com/proof',
      'attachments/missing.pdf',
      'attachments/alias.pdf',
      'attachments/../outside.pdf',
    ],
    'futureExtension': {
      'priority': ['high'],
    },
  });
  final source = <String, Object?>{
    'professions': ['Dentistry', 'Old scheme'],
    'deleted_professions': ['OLD SCHEME'],
    'next_entry_id': 2,
    'targets_v1': '{"dentistry":{"minutes":150,"cycle":"month"}}',
    'entries_json_list': [
      raw,
      raw,
      _legacyRow({'profession': 'Old scheme', 'deleted': true}),
      _legacyRow({'profession': 'Orphan'}),
    ],
  };
  final path = p.join(scratch.path, 'migration.sqlite');
  var db = await SqliteRecordingRepository.open(path);
  try {
    var migration = SyntheticCpdMigration(db, scratch);
    _check(
      await migration.stage(source) == ImportStatus.staged,
      'migration stages',
    );
    final staged = (await migration.inspect(source))!;
    final rawSource = jsonDecode(staged.raw) as Map;
    _check(
      (rawSource['entries_json_list'] as List).first == raw,
      'original JSON, including unknown extension, is byte-identical',
    );
    final metadata = jsonDecode(staged.metadata!) as Map;
    final groups = metadata['collections'] as Map;
    final dentist = groups['dentistry'] as String;
    final target = (metadata['targets'] as Map)[dentist] as Map;
    _check(
      target['minutes'] == 150 && target['cycle'] == 'month',
      'target preserved against collection ID',
    );
    final records = await db.loadRecords(dentist);
    _check(
      records.length == 2 && records.first.id != records.last.id,
      'duplicate legacy IDs remain distinct rows',
    );
    final fields = (await db.loadLayouts(dentist)).single.fields;
    final evidence = fields.singleWhere(
      (field) => field.definition.id == 'cpd.evidence',
    );
    final duration = fields.singleWhere(
      (field) => field.definition.id == 'cpd.creditedDuration',
    );
    final day = fields.singleWhere(
      (field) => field.definition.id == 'cpd.activityDate',
    );
    _check(
      records.first.values[duration.id] == 65 &&
          records.first.values[day.id] == '2024-02-29',
      'durations and calendar dates preserved',
    );
    final links = [
      for (final id
          in (records.first.values[evidence.id] as List).cast<String>())
        (await db.loadAttachment(id))!,
    ];
    _check(
      links.map((link) => link.kind.name).join(',') ==
          'managed,managed,link,unresolved,unresolved,unresolved',
      'ordered link, rebase, missing, symlink and unsafe path classification',
    );
    final retired = groups['old scheme'] as String;
    _check(
      (await db.loadCollection(retired))!.deleted &&
          (await db.loadRecords(
            retired,
            includeDeleted: true,
          )).single.deleted &&
          (await db.loadCollection(groups['orphan'] as String))!.deleted,
      'profession and record tombstones and orphan recovery',
    );
    await db.close();
    db = await SqliteRecordingRepository.open(path);
    migration = SyntheticCpdMigration(db, scratch);
    await original.writeAsBytes([7, 0, 9]);
    await _rejects<StateError>(() => migration.verify(source));
    _check(
      (await migration.inspect(source))!.status == ImportStatus.staged,
      'changed proof blocks verification after reopen',
    );
    await original.writeAsBytes([7, 0, 3]);
    await migration.verify(source);
    _check(
      await migration.stage(source) == ImportStatus.verified &&
          (await migration.inspect(source))!.verifiedAt != null &&
          jsonEncode(await original.readAsBytes()) == '[7,0,3]',
      'restart verifies once with no duplicate rows or original modifications',
    );
  } finally {
    await db.close();
  }
}

Future<void> _blockedMigration(Directory scratch) async {
  final db = await SqliteRecordingRepository.open(
    p.join(scratch.path, 'blocked.sqlite'),
  );
  try {
    final runner = SyntheticCpdMigration(db, scratch);
    final source = <String, Object?>{
      'professions': ['Dentistry'],
      'entries_json_list': [
        _legacyRow({}),
        _legacyRow({'date': '2025-02-30'}),
        _legacyRow({'minutes': 1.5}),
        _legacyRow({'date': '2025-01-01T00:00:00Z'}),
        '{"bad row":',
        _legacyRow({}).replaceFirst('"id":1', r'"\u0069d":2,"id":1'),
      ],
      'targets_v1':
          '{"Dentistry":{"minutes":150,"cycle":"month"},'
          '"DENTISTRY":{"minutes":120,"cycle":"year"}}',
    };
    _check(
      await runner.stage(source) == ImportStatus.blocked,
      'ambiguous source blocks staging',
    );
    final snapshot = (await runner.inspect(source))!;
    final diagnostics =
        (jsonDecode(snapshot.metadata!) as Map)['issues'] as List;
    _check(
      diagnostics.where((issue) => issue['blocks'] == true).length == 6 &&
          (jsonDecode(snapshot.raw) as Map)['targets_v1'] ==
              source['targets_v1'],
      'all ambiguous rows and both targets are accounted for',
    );
    final group =
        ((jsonDecode(snapshot.metadata!) as Map)['collections']
            as Map)['dentistry'];
    _check(
      await db.loadCollection(group as String) == null &&
          snapshot.verifiedAt == null,
      'blocked migration has no destination records or verified marker',
    );
    await _rejects<StateError>(() => runner.verify(source));
  } finally {
    await db.close();
  }
}

String _legacyRow(Map<String, Object?> overrides) => jsonEncode({
  'id': 1,
  'profession': 'Dentistry',
  'date': '2024-02-29T00:00:00.000',
  'title': 'Synthetic training',
  'details': 'Ligne 1\n学習',
  'hours': 1,
  'minutes': 5,
  ...overrides,
});

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<void> _rejects<T>(Future<Object?> Function() operation) async {
  try {
    await operation();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T.');
}
