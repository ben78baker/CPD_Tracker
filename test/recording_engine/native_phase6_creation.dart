import 'dart:io';

import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'phase6_rehearsal_app.dart' show phase6Store;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Verifying Phase 6 creation'))),
    ),
  );
  final sandbox = await Directory.systemTemp.createTemp('phase6_native_');
  try {
    await _verify(p.join(sandbox.path, 'phase6.sqlite'));
    debugPrintSynchronously(
      'PHASE6_NATIVE_PASS: creation, grants, drafts, scoped editing, reporting and history',
    );
  } catch (error, stack) {
    debugPrintSynchronously('PHASE6_NATIVE_FAIL: $error\n$stack');
    rethrow;
  } finally {
    await sandbox.delete(recursive: true);
  }
}

Future<void> _verify(String path) async {
  var db = await SqliteRecordingRepository.open(path);
  var host = phase6Store(db);
  Future<void> reopen() async {
    await db.close();
    db = await SqliteRecordingRepository.open(path);
    host = phase6Store(db);
  }

  final product = 'template:${nursingPilot.id}';
  try {
    _check(await host.startup() == CreationStartup.welcome, 'first launch');
    _check(
      await host.startup(confirmedLegacyHistory: true) == CreationStartup.home,
      'legacy installation',
    );
    await host.saveSetting('accent', 'teal');
    await host.saveSetting('welcome', 'true');
    await host.saveSetting('offline', 'true');
    _check(
      await host.startup() == CreationStartup.resumeCreation,
      'resume onboarding',
    );
    await _reject<StateError>(() => host.begin(ProfessionKind.custom));
    await _reject<StateError>(
      () => host.begin(ProfessionKind.template, recipe: nursingPilot),
    );

    var standard = await host.begin(ProfessionKind.standard);
    standard = standard.withChanges(name: 'Practice');
    await host.persist(standard);
    final concurrent = (await host.begin(
      ProfessionKind.standard,
    )).withChanges(name: ' pRACTICE ');
    await host.persist(concurrent);
    await reopen();
    _check((await host.drafts()).length == 2, 'drafts survive restart');
    _check(
      (await host.settings())['accent'] == 'teal',
      'preferences survive restart',
    );
    _check(
      (await db.loadCollections()).isEmpty,
      'drafts do not create records or tiles',
    );
    final created = await host.commit(standard.id, firstProfession: true);
    await _reject<ProfessionNameException>(
      () => host.commit(concurrent.id, firstProfession: true),
    );
    await reopen();
    _check(
      await host.startup() == CreationStartup.home,
      'completion repaired after durable first creation',
    );
    _check(
      await host.commit(standard.id, firstProfession: true) == created,
      'duplicate commit returns original collection',
    );
    _check((await db.loadCollections()).length == 1, 'only one standard tile');
    _check(
      (await db.loadLayouts(created)).last.fields.length == 5,
      'offline Standard has five free fields',
    );
    await host.discard(concurrent.id);

    await _reject<StateError>(() => host.startSimulatedPurchase(product));
    await host.saveSetting('offline', 'false');
    await host.startSimulatedPurchase(product);
    final cancelledAttempt = (await host.purchaseStates())['attempt:$product'];
    await host.acceptSimulatedPurchase(product, PurchaseState.cancelled);
    await _reject<StateError>(
      () => host.begin(ProfessionKind.template, recipe: nursingPilot),
    );
    await host.startSimulatedPurchase(product);
    await host.acceptSimulatedPurchase(
      product,
      PurchaseState.cancelled,
      attempt: cancelledAttempt,
    );
    await host.saveSetting('offline', 'true');
    await reopen();
    _check(
      (await host.purchaseStates())[product] == 'pending',
      'pending purchase survives termination',
    );
    await host.acceptSimulatedPurchase(product, PurchaseState.verified);
    await host.acceptSimulatedPurchase(product, PurchaseState.pending);
    final abandoned = await host.begin(
      ProfessionKind.template,
      recipe: nursingPilot,
    );
    await host.discard(abandoned.id);
    await reopen();
    _check(
      (await host.access()).templates.contains(nursingPilot.id),
      'ownership survives abandoned draft and offline reopen',
    );
    _check(
      !(await host.access()).canCustomiseFields,
      'template does not grant app-wide editing',
    );
    await _reject<StateError>(() => host.begin(ProfessionKind.custom));

    final firstTemplate = (await host.begin(
      ProfessionKind.template,
      recipe: nursingPilot,
    )).withChanges(name: 'Clinical log');
    await host.persist(firstTemplate);
    final placement = await host.commit(firstTemplate.id);
    final second = (await host.begin(
      ProfessionKind.template,
      recipe: nursingPilot,
    )).withChanges(name: 'Agency log');
    await host.persist(second);
    final other = await host.commit(second.id);
    final original = (await db.loadLayouts(placement)).last;
    final otherLayout = (await db.loadLayouts(other)).last;
    _check(
      !original.fields.any(
        (f) => otherLayout.fields.any((another) => another.id == f.id),
      ),
      'placements have separate field IDs',
    );

    final recipeFieldIds = {
      for (final (index, field) in nursingPilot.fields.indexed)
        field.id: original.fields[index].id,
    };
    final example = nursingExamples(nursingPilot).first.values;
    final values = {
      for (final v in example.entries) recipeFieldIds[v.key]!: v.value,
    };
    final record = await db.createRecord(
      placement,
      values,
      expectedLayoutVersion: original.version,
      newAttachments: [
        RecordingAttachment(
          id: 'preview.sample',
          kind: AttachmentKind.link,
          locator: 'https://example.com/sample',
          name: 'Synthetic agenda',
        ),
      ],
    );
    final optional = original.fields.singleWhere(
      (field) => field.definition.id == 'nmc.practice',
    );
    final required = original.fields.singleWhere(
      (field) => field.definition.id == 'nmc.method',
    );
    var edit = await host.beginEdit(placement);
    edit.layout.configure(
      LayoutField(
        id: optional.id,
        definition: optional.definition,
        labelOverride: 'Unofficial rename',
      ),
    );
    await host.persist(edit);
    await _reject<StateError>(() => host.commit(edit.id));
    await host.discard(edit.id);
    edit = await host.beginEdit(placement);
    edit.layout.retire(required.id);
    await host.persist(edit);
    await _reject<StateError>(
      () => host.commit(edit.id, acceptIncomplete: true),
    );
    await host.discard(edit.id);
    edit = await host.beginEdit(placement);
    await host.persist(
      edit.withChanges(report: ReportSelection(excluded: [required.id])),
    );
    await _reject<StateError>(
      () => host.commit(edit.id, acceptIncomplete: true),
    );
    await host.discard(edit.id);

    edit = await host.beginEdit(placement);
    edit.layout.move(optional.id, 0);
    final reportOnly = edit.withChanges(
      report: ReportSelection(excluded: [optional.id]),
    );
    await host.persist(reportOnly);
    await host.commit(edit.id);
    final afterReport = (await db.loadLayouts(placement)).last;
    _check(
      afterReport.fields.first.id == optional.id,
      'reorder and report exclusion independent',
    );
    _check(
      (await host.reportAt(
        placement,
        afterReport.version,
      )).excluded.contains(optional.id),
      'new report exclusion',
    );
    _check(
      (await host.reportAt(placement, original.version)).excluded.isEmpty,
      'historical report unchanged',
    );

    edit = await host.beginEdit(placement);
    edit.layout.retire(optional.id);
    await host.persist(edit.withChanges(report: ReportSelection()));
    await reopen();
    edit = (await host.drafts()).single;
    _check(
      !edit.layout.fields.any((f) => f.id == optional.id),
      'edit draft resumes with staged removal',
    );
    _check(
      (await db.loadLayouts(
        placement,
      )).last.fields.any((f) => f.id == optional.id),
      'staged edit leaves saved layout intact',
    );
    await host.commit(edit.id);
    final absent = (await db.loadLayouts(placement)).last;
    final laterValues = Map<String, Object>.of(values)..remove(optional.id);
    final gap = await db.createRecord(
      placement,
      laterValues,
      expectedLayoutVersion: absent.version,
    );
    edit = await host.beginEdit(placement);
    edit.layout.reinstate(optional);
    await host.persist(edit);
    await host.commit(edit.id);
    final allRevisions = await db.loadLayouts(placement);
    _check(
      allRevisions.last.fields.any((f) => f.id == optional.id),
      'same supplied field reinstated',
    );
    _check(
      !resolveFields(
        gap.layoutVersion,
        allRevisions,
      ).any((f) => f.id == optional.id),
      'no retrospective field insertion',
    );
    _check(
      (await db.loadRecord(record.id))!.values[optional.id] ==
          example[nursingPilot.fields
              .singleWhere((f) => f.definition.id == 'nmc.practice')
              .id],
      'historic values survive removal and reinstatement',
    );
    _check(
      (await db.loadLayouts(other)).last.version == otherLayout.version,
      'second placement unaffected',
    );

    await host.verifySimulatedOriginalPurchase();
    await reopen();
    _check(
      (await host.access()).legacy,
      'verified original grant survives offline restart',
    );
    final customised = (await host.begin(
      ProfessionKind.custom,
    )).withChanges(name: 'Independent');
    await host.persist(customised);
    await host.commit(customised.id);
    edit = await host.beginEdit(placement);
    edit.layout.retire(required.id);
    await host.persist(edit);
    await _reject<StateError>(() => host.commit(edit.id));
    await host.commit(edit.id, acceptIncomplete: true);
    final combined = (await db.loadLayouts(placement)).last;
    _check(
      nursingReportRules
          .assess(original, LayoutDraft(combined), ReportSelection())
          .incomplete,
      'combined access preserves incompatible report status',
    );
    _check(
      await host.requireOwnedReport(combined) == nursingReportRules,
      'owned report version',
    );
    _check(
      (await db.loadRecord(record.id))!.values.containsKey(required.id),
      'combined edits preserve old value',
    );
    _check(
      (await nursingSampleReport(nursingPilot, ReportSelection())).isNotEmpty,
      'report generates',
    );
  } finally {
    await db.close();
  }
}

void _check(bool value, String label) {
  if (!value) throw StateError(label);
}

Future<void> _reject<T extends Object>(Future<Object?> Function() run) async {
  try {
    await run();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected rejection: $T');
}
