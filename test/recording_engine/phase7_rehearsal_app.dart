import 'dart:io';

import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'phase6_rehearsal_app.dart';
import 'phase7_rehearsal_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(
    p.join((await getApplicationSupportDirectory()).path, 'phase7_rehearsal'),
  );
  final originals = ManagedAttachmentFiles(root);
  runApp(
    Phase6App(
      phase7: true,
      originals: originals,
      open: () async {
        await root.create(recursive: true);
        final repository = await SqliteRecordingRepository.open(
          p.join(root.path, 'sandbox.sqlite'),
        );
        final store = phase6Store(repository);
        if (const bool.fromEnvironment('PHASE7_SAMPLES') &&
            (await repository.loadCollections()).isEmpty) {
          await seedPhase7(store, root);
        }
        return store;
      },
    ),
  );
}

/// Separate synthetic rehearsal fixture, never imported by the application.
Future<(String, String)> seedPhase7(
  ProfessionCreationStore store,
  Directory root,
) async {
  final repository = store.repository;
  final bundle = nursingBundle;
  Future<String> create(ProfessionKind kind, String label) async {
    final draft = (await store.begin(
      kind,
      recipe: kind == ProfessionKind.template ? bundle.recipe : null,
    )).withChanges(name: label);
    await store.persist(draft);
    return store.commit(
      draft.id,
      firstProfession: kind == ProfessionKind.standard,
    );
  }

  await create(ProfessionKind.standard, 'Standard CPD · Mentoring');
  await store.acceptSimulatedPurchase(
    'template:${bundle.recipe.id}',
    PurchaseState.verified,
  );
  final first = await create(
    ProfessionKind.template,
    'Nursing · Community practice',
  );
  final second = await create(
    ProfessionKind.template,
    'Midwifery · Hospital practice',
  );
  final periods = SchemePeriodStore(repository);
  await periods.select(
    first,
    SchemePeriod.create(
      bundle,
      id: 'previous',
      kind: PeriodKind.fixed,
      anchor: '2021-01-01',
      deadline: '2023-12-01',
    ),
  );
  await periods.select(first, rehearsalPeriod);
  await periods.select(
    second,
    SchemePeriod.create(
      bundle,
      id: 'midwifery',
      kind: PeriodKind.fixed,
      anchor: '2026-09-01',
    ),
  );
  final sampleFile = await File(
    p.join(root.path, 'attendance.txt'),
  ).writeAsString('Synthetic attendance evidence.');
  final original = await ManagedAttachmentFiles(root).copyOriginal(sampleFile);
  await sampleFile.delete();
  final link = RecordingAttachment(
    id: 'demo.link',
    kind: AttachmentKind.link,
    locator: 'https://example.com/synthetic-evidence',
    name: 'Synthetic reference link',
  );
  final unresolved = RecordingAttachment(
    id: 'demo.missing',
    kind: AttachmentKind.unresolved,
    locator: 'missing/attendance.pdf',
    name: 'Attendance confirmation.pdf',
  );
  await repository.saveAttachment(original);
  await repository.saveAttachment(link);
  await repository.saveAttachment(unresolved);
  for (final id in [first, second]) {
    final history = await repository.loadLayouts(id);
    final binding = adoptedRecipeFields(
      bundle,
      history.firstWhere((item) => item.templateId != null),
    );
    final samples = id == first ? bundle.examples : bundle.examples.take(1);
    for (final (index, example) in samples.indexed) {
      await repository.createRecord(id, {
        for (final value in example.values.entries)
          binding[value.key]!.id:
              value.key == bundle.inputs[ActivityInput.evidence]
              ? [index == 0 ? original.id : link.id]
              : value.value,
      }, expectedLayoutVersion: history.last.version);
    }
    if (id == first) {
      final sample = bundle.examples.first;
      await repository.createRecord(id, {
        for (final value in sample.values.entries)
          binding[value.key]!.id:
              value.key == bundle.inputs[ActivityInput.evidence]
              ? [unresolved.id]
              : value.key == bundle.inputs[ActivityInput.title]
              ? 'Simulation debrief with evidence pending'
              : value.value,
      }, expectedLayoutVersion: history.last.version);
    }
  }
  return (first, second);
}
