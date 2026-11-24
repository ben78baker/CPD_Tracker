import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;

void check(bool valid, String message) {
  if (!valid) throw StateError(message);
}

Future<void> rejects<T>(Future<void> Function() apply) async {
  try {
    await apply();
  } on Object catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected ${T.toString()}.');
}

Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Use a disposable debug app.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Synthetic template adoption validation')),
    ),
  );
  final root = await Directory.systemTemp.createTemp('cpd_owned_template_');
  final db = await SqliteRecordingRepository.open(
    RecordingWorkspace(root).databasePath,
  );
  try {
    await verifyAdoption(db);
    debugPrintSynchronously('CPD_OWNED_TEMPLATE_PASS');
  } on Object catch (error, trace) {
    debugPrintSynchronously('CPD_OWNED_TEMPLATE_FAIL $error\n$trace');
    rethrow;
  } finally {
    await db.close();
    await root.delete(recursive: true);
  }
}

Future<void> verifyAdoption(SqliteRecordingRepository db) async {
  final recipe = nursingPilot;
  final key = (recipe.id, recipe.version);
  final store = ProfessionCreationStore(
    db,
    templates: {key: recipe},
    reportRules: {key: nursingReportRules},
    bundles: {key: nursingBundle},
  );
  final standard = await db.createCollection(
    'Existing Standard',
    fields: cpdStandardFields('existing-standard'),
  );
  final active = (await db.loadLayouts(standard.id)).single;
  final fields = cpdFieldBindings(active.fields);
  final date = fields['cpd.activityDate']!;
  final title = fields['cpd.title']!;
  final duration = fields['cpd.creditedDuration']!;
  final before = await store.createActivity(standard.id, {
    date: '2026-10-14',
    title: 'Earlier activity',
    duration: 65,
  }, expectedLayoutVersion: active.version);
  await store.verifySimulatedOriginalPurchase();
  await rejects<StateError>(
    () => store.applyOwnedTemplate(
      standard.id,
      key,
      expectedLayoutVersion: active.version,
    ),
  );
  await store.acceptSimulatedPurchase(
    'template:${recipe.id}',
    PurchaseState.verified,
  );
  final edit = await store.beginEdit(standard.id);
  final reordered = edit.layout;
  reordered.move(title, 0);
  await store.persist(
    edit.withChanges(report: ReportSelection(excluded: [title])),
  );
  await rejects<PendingProfessionDraftException>(
    () => store.applyOwnedTemplate(
      standard.id,
      key,
      expectedLayoutVersion: active.version,
    ),
  );
  check((await store.drafts()).single.id == edit.id, 'Changed draft was lost.');
  await store.commit(edit.id);
  final customLayout = (await db.loadLayouts(standard.id)).last;
  check(
    (await store.reportAt(
      standard.id,
      customLayout.version,
    )).excluded.contains(title),
    'The old report selection was not saved.',
  );
  final adoption = await store.applyOwnedTemplate(
    standard.id,
    key,
    expectedLayoutVersion: customLayout.version,
  );
  check(
    adoption.templateId == recipe.id && adoption.includeExisting.isEmpty,
    'The template did not apply to future records only.',
  );
  final retained = (await db.loadRecord(before.id))!;
  check(
    retained.layoutVersion == before.layoutVersion &&
        retained.values[duration] == 65,
    'The original record changed.',
  );
  final edited = await store.editActivity(retained, {
    title: 'Updated old activity',
  }, expectedLayoutVersion: adoption.version);
  check(
    edited.layoutVersion == before.layoutVersion,
    'Historical edit switched layouts.',
  );
  await rejects<StateError>(
    () => store.applyOwnedTemplate(
      standard.id,
      key,
      expectedLayoutVersion: adoption.version,
    ),
  );

  final example = nursingExamples(recipe).first.values;
  final record = await store.createActivity(
    standard.id,
    {
      for (final (index, field) in recipe.fields.indexed)
        adoption.fields[index].id: ?example[field.id],
    },
    expectedLayoutVersion: adoption.version,
    newAttachments: [
      RecordingAttachment(
        id: 'preview.sample',
        kind: AttachmentKind.link,
        locator: 'https://example.com/synthetic-evidence',
        name: 'Synthetic evidence',
      ),
    ],
  );
  final periods = SchemePeriodStore(db);
  await periods.select(standard.id, rehearsalPeriod);
  final progress = await loadSchemeProgress(
    repository: db,
    bundle: nursingBundle,
    period: rehearsalPeriod,
    history: await db.loadLayouts(standard.id),
    records: await db.loadRecords(standard.id),
  );
  check(
    progress.progress.activities.single.activity.id == record.id &&
        progress.progress.metrics['total']!.recorded == 120,
    'Scheme progress included an activity created before adoption.',
  );

  final second = await db.createCollection(
    'Second existing profession',
    fields: active.fields.map((f) => f.reidentify('second-${f.id}')),
  );
  final secondAdoption = await store.applyOwnedTemplate(
    second.id,
    key,
    expectedLayoutVersion: second.layoutVersion,
  );
  check(
    secondAdoption.templateId == adoption.templateId &&
        secondAdoption.fields.first.id != adoption.fields.first.id,
    'The owned template could not be applied as an independent layout.',
  );
}
