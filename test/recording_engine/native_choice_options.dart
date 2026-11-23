import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_backup/cpd_collection_backup.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/original_directory_sync.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejectOption(Future<void> Function() write) async {
  try {
    await write();
  } on ArgumentError {
    return;
  }
  throw StateError('Invalid options were accepted.');
}

LayoutField field(String id, FieldKind kind) => LayoutField(
  id: id,
  definition: FieldDefinition(
    id: id,
    version: 1,
    label: id,
    kind: kind,
    choices: const {'base': 'Workshop'},
    allowCustomOptions: true,
  ),
);

Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Use a disposable debug app.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Text('Synthetic choice validation')),
    ),
  );
  final root = await Directory.systemTemp.createTemp('cpd_choice_options_');
  try {
    await verifyChoiceOptions(root);
    debugPrintSynchronously('CPD_CHOICE_OPTIONS_PASS');
  } on Object catch (error, trace) {
    debugPrintSynchronously('CPD_CHOICE_OPTIONS_FAIL $error\n$trace');
    rethrow;
  } finally {
    await root.delete(recursive: true);
  }
}

Future<void> verifyChoiceOptions(Directory root) async {
  final workspace = RecordingWorkspace(root);
  await workspace.originals.create();
  final originals = ManagedAttachmentFiles(
    workspace.originals,
    syncDirectory: syncOriginalDirectory,
  );
  final backup = cpdCollectionBackup((_) async => 64 * 1024 * 1024);
  var repository = await SqliteRecordingRepository.open(workspace.databasePath);
  ProfessionCreationStore host() => ProfessionCreationStore(
    repository,
    templates: const {},
    reportRules: const {},
  );
  const single = 'Delivery';
  const multi = 'Topics';
  try {
    final group = await repository.createCollection(
      'Synthetic delivery',
      fields: [
        ...cpdStandardFields('choice-fixture'),
        field(single, FieldKind.choice),
        field(multi, FieldKind.multipleChoices),
      ],
    );
    final layout = (await repository.loadLayouts(group.id)).single;
    final bindings = cpdFieldBindings(layout.fields);
    Map<String, Object> activity(String title) => {
      bindings['cpd.title']!: title,
      bindings['cpd.activityDate']!: '2026-10-20',
      bindings['cpd.creditedDuration']!: 15,
    };
    final rawOnce = storeChoiceSelection((id: null, text: 'Evening session'));
    final once = await host().createActivity(group.id, {
      ...activity('Use once'),
      single: rawOnce,
    }, expectedLayoutVersion: 1);
    check(
      (await repository.loadLayouts(group.id)).length == 1,
      'Use once must not change the layout.',
    );
    await repository.saveHostValue(
      ProfessionCreationStore.reportsNamespace,
      '${group.id}:1',
      jsonEncode([multi]),
    );
    final reusable = storeChoiceSelection((id: 'saved', text: 'Peer study'));
    final saved = await host().createActivity(
      group.id,
      {...activity('Reusable'), single: reusable},
      expectedLayoutVersion: 1,
      addedOptions: {
        single: {'saved': 'Peer study'},
      },
    );
    check(saved.layoutVersion == 2, 'Save as option publishes a new revision.');
    check(
      (await host().reportAt(group.id, 2)).excluded.contains(multi),
      'Report settings follow the new revision.',
    );
    final team = storeChoiceSelection((id: 'team', text: 'Team learning'));
    final edited = await host().editActivity(
      once,
      {
        multi: ['base', team],
      },
      expectedLayoutVersion: 2,
      addedOptions: {
        multi: {'team': 'Team learning'},
      },
    );
    check(
      edited.layoutVersion == 1,
      'An edit must keep the record’s original revision.',
    );
    final history = await repository.loadLayouts(group.id);
    final historical = resolveFields(edited.layoutVersion, history);
    check(
      edited.project(historical).contains('Evening session') &&
          (historical
                          .singleWhere((field) => field.id == multi)
                          .definition
                          .displayValue(edited.values[multi]!)
                      as List)
                  .join(', ') ==
              'Workshop, Team learning',
      'Historical labels, including mixed predefined and custom choices, survive editing.',
    );
    await rejectOption(() async {
      await repository.addFieldOptions(group.id, {
        single: {'duplicate': '  PEER   Study '},
      }, expectedLayoutVersion: 3);
    });
    await rejectOption(() async {
      await host().createActivity(
        group.id,
        {...activity('Rejected'), single: 'not-a-predefined-option'},
        expectedLayoutVersion: 3,
        addedOptions: {
          single: {'rollback': 'Rollback choice'},
        },
      );
    });
    check(
      (await repository.loadLayouts(group.id)).length == 3 &&
          (await repository.loadRecords(group.id)).length == 2,
      'Rejection must roll back both the option and the record.',
    );

    await repository.saveTemplate(nursingPilot);
    final templateGroup = await repository.createCollection('Synthetic NMC');
    final applied = await repository.applyTemplate(
      templateGroup.id,
      nursingPilot,
      expectedVersion: 1,
    );
    for (final controlled in applied.fields.where(
      (field) =>
          field.definition.kind == FieldKind.choice ||
          field.definition.kind == FieldKind.multipleChoices,
    )) {
      await rejectOption(() async {
        await repository.addFieldOptions(templateGroup.id, {
          controlled.id: {'denied': 'Unreviewed'},
        }, expectedLayoutVersion: applied.version);
      });
    }
    final explicit = TemplateVersion(
      id: 'synthetic-permitted',
      version: 1,
      label: 'Synthetic flexible recipe',
      origin: TemplateOrigin.bundled,
      fields: [field('Approved flexible', FieldKind.choice)],
    );
    await repository.saveTemplate(explicit);
    final allowedGroup = await repository.createCollection('Synthetic allowed');
    final allowed = await repository.applyTemplate(
      allowedGroup.id,
      explicit,
      expectedVersion: 1,
    );
    final withOption = await repository.addFieldOptions(allowedGroup.id, {
      allowed.fields.single.id: {'local': 'Local option'},
    }, expectedLayoutVersion: allowed.version);
    final retained = await repository.loadTemplate(explicit.id, 1);
    check(
      withOption.templateVersion == 1 &&
          withOption.fields.single.addedOptions['local'] == 'Local option' &&
          retained!.fields.single.addedOptions.isEmpty,
      'Explicit permission enables local options without rewriting the template.',
    );

    await repository.close();
    repository = await SqliteRecordingRepository.open(workspace.databasePath);
    final reopened = (await repository.loadLayouts(group.id)).last;
    check(
      reopened.fields
              .singleWhere((field) => field.id == multi)
              .addedOptions['team'] ==
          'Team learning',
      'Reusable options survive reopening SQLite.',
    );
    final exported = await backup.create(
      repository: repository,
      collectionId: group.id,
      originals: originals.root,
      temporary: root,
    );
    final candidate = await backup.inspect(
      source: await exported.fileForSharing(),
      temporary: root,
    );
    final destination = await SqliteRecordingRepository.open(
      p.join(root.path, 'restore.sqlite'),
    );
    try {
      final imported = await backup.restore(
        review: candidate,
        repository: destination,
        originals: originals,
        label: 'Restored synthetic delivery',
      );
      final restored = imported.collection!;
      final layouts = await destination.loadLayouts(restored.id);
      final latest = layouts.last;
      final values = await destination.loadRecords(restored.id);
      check(
        latest.fields
                    .singleWhere((field) => field.id == single)
                    .addedOptions['saved'] ==
                'Peer study' &&
            latest.fields
                    .singleWhere((field) => field.id == multi)
                    .addedOptions['team'] ==
                'Team learning' &&
            values.any(
              (record) => record
                  .project(resolveFields(record.layoutVersion, layouts))
                  .contains('Evening session'),
            ) &&
            values.any(
              (record) => record
                  .project(resolveFields(record.layoutVersion, layouts))
                  .contains('Peer study'),
            ),
        'Backup/restore preserves reusable options and historical labels.',
      );
      check(
        latest.fields
                .singleWhere((field) => field.id == single)
                .addedOptions
                .length ==
            1,
        'The one-off value must not become a reusable option on restore.',
      );
    } finally {
      await destination.close();
      await candidate.dispose();
      await exported.dispose();
    }
  } finally {
    await repository.close();
  }
}
