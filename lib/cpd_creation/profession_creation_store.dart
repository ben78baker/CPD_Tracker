import 'historical_bundles.dart';
import 'template_bundle.dart';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../cpd_compatibility/cpd_data_store.dart';
import '../cpd_compatibility/cpd_duration.dart';
import '../cpd_compatibility/cpd_layout_policy.dart';
import '../cpd_migration/legacy_migration.dart' show cpdStandardFields;
import '../recording_engine/layout_draft.dart';
import '../recording_engine/models.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import 'creation_policy.dart';
import 'template_evaluation.dart';

class ProfessionDraft {
  ProfessionDraft({
    required this.id,
    required this.kind,
    required this.layout,
    required this.report,
    this.name = '',
    this.templateId,
    this.templateVersion,
    this.editing,
  });

  final String id;
  final ProfessionKind kind;
  final LayoutDraft layout;
  final ReportSelection report;
  final String name;
  final String? templateId;
  final int? templateVersion;
  final String? editing;

  ProfessionDraft withChanges({
    String? name,
    LayoutDraft? layout,
    ReportSelection? report,
  }) => ProfessionDraft(
    id: id,
    kind: kind,
    layout: layout ?? this.layout,
    report: report ?? this.report,
    name: name ?? this.name,
    templateId: templateId,
    templateVersion: templateVersion,
    editing: editing,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'layout': layout.toJson(),
    'template': templateId,
    'version': templateVersion,
    'editing': editing,
    'report': report.toJson(),
  };

  factory ProfessionDraft.fromJson(Map<String, dynamic> json) =>
      ProfessionDraft(
        id: json['id'] as String,
        kind: ProfessionKind.values.byName(json['kind'] as String),
        layout: LayoutDraft.fromJson(
          json['layout'] as Map<String, dynamic>,
          maxActiveFields: cpdActiveFieldLimit,
        ),
        report: ReportSelection.fromJson(json['report'] as List),
        name: json['name'] as String,
        templateId: json['template'] as String?,
        templateVersion: json['version'] as int?,
        editing: json['editing'] as String?,
      );
}

enum NameProblem { blank, exists, deleted }

enum CreationStartup { welcome, resumeCreation, home }

class PendingProfessionDraftException implements Exception {
  const PendingProfessionDraftException();
}

/// The CPD application boundary. Only the disposable Phase 6 entry point
/// constructs this service. Purchases and drafts have independent lifetimes.
class ProfessionCreationStore {
  ProfessionCreationStore(
    this.repository, {
    required Map<(String, int), TemplateVersion> templates,
    required Map<(String, int), SchemeReportRules> reportRules,
    Map<(String, int), ProfessionTemplateBundle> bundles = const {},
    this.evaluationLedger,
  }) : templates = Map.unmodifiable(templates),
       reportRules = Map.unmodifiable(reportRules),
       bundles = Map.unmodifiable(bundles);

  final SqliteRecordingRepository repository;
  final Map<(String, int), TemplateVersion> templates;
  final Map<(String, int), SchemeReportRules> reportRules;

  final Map<(String, int), ProfessionTemplateBundle> bundles;
  final TemplateEvaluationLedger? evaluationLedger;

  bool get evaluationsEnabled => evaluationLedger != null;

  static const _uuid = Uuid();
  static const draftsNamespace = 'cpd.creation.drafts';
  static const _receipts = 'cpd.creation.receipts';
  static const _settings = 'cpd.creation.settings';
  static const grantsNamespace = 'cpd.creation.grants';
  static const reportsNamespace = 'cpd.creation.reports';
  static const customProduct = 'custom-fields';

  Future<Map<String, String>> settings() => repository.loadHostState(_settings);
  Future<void> saveSetting(String key, String value) =>
      repository.saveHostValue(_settings, key, value);

  Future<CreationStartup> startup({bool confirmedLegacyHistory = false}) =>
      repository.transaction((tx) async {
        final settings = await tx.loadHostState(_settings);
        if (settings['complete'] == 'true') return CreationStartup.home;
        final first = settings['firstProfession'];
        if (first != null) {
          if (await tx.loadCollection(first) == null ||
              (await tx.loadLayouts(first)).isEmpty) {
            throw StateError(
              'The saved first profession could not be recovered.',
            );
          }
          await tx.saveHostValue(_settings, 'complete', 'true');
          return CreationStartup.home;
        }
        if (confirmedLegacyHistory || (await tx.loadCollections()).isNotEmpty) {
          return CreationStartup.home;
        }
        return settings['welcome'] == 'true'
            ? CreationStartup.resumeCreation
            : CreationStartup.welcome;
      });

  Future<CreationAccess> access() => _access(repository);
  Future<CreationAccess> _access(SqliteRecordingRepository tx) async {
    final permanent = await _permanentAccess(tx);
    if (!evaluationsEnabled) return permanent;
    return CreationAccess(
      customFields: permanent.customFields,
      legacy: permanent.legacy,
      templates: permanent.templates,
      evaluationTemplates: templates.keys.map((key) => key.$1),
    );
  }

  Future<CreationAccess> _permanentAccess(SqliteRecordingRepository tx) async {
    final state = await tx.loadHostState(grantsNamespace);
    return CreationAccess(
      customFields: state[customProduct] == PurchaseState.verified.name,
      legacy: state['legacy'] == PurchaseState.verified.name,
      templates: state.entries
          .where(
            (entry) =>
                entry.key.startsWith('template:') &&
                entry.value == PurchaseState.verified.name,
          )
          .map((entry) => entry.key.substring(9)),
    );
  }

  Future<TemplateEvaluationStatus> evaluationStatus(String id) async {
    if ((await _permanentAccess(repository)).templates.contains(id)) {
      return const TemplateEvaluationStatus(owned: true);
    }
    final ledger = evaluationLedger;
    if (ledger != null && _knownTemplate(id)) {
      return ledger.status(repository, id);
    }
    return const TemplateEvaluationStatus();
  }

  bool _knownTemplate(String id) => templates.keys.any((key) => key.$1 == id);

  Future<Map<String, String>> purchaseStates() =>
      repository.loadHostState(grantsNamespace);

  /// The rehearsal store's persisted attempts and grants are independent of
  /// creation requests. A repeated or older callback cannot undo a grant.
  Future<void> acceptSimulatedPurchase(
    String product,
    PurchaseState state, {
    String? attempt,
  }) => repository.transaction((tx) async {
    _checkProduct(product);
    final ledger = await tx.loadHostState(grantsNamespace);
    if (ledger[product] == PurchaseState.verified.name) return;
    if (attempt != null && ledger['attempt:$product'] != attempt) return;
    if (ledger[product] == PurchaseState.cancelled.name &&
        state == PurchaseState.pending) {
      return;
    }
    await tx.saveHostValue(grantsNamespace, product, state.name);
  });

  Future<void> startSimulatedPurchase(String product) =>
      repository.transaction((tx) async {
        _checkProduct(product);
        if ((await tx.loadHostState(_settings))['offline'] == 'true') {
          throw StateError('The rehearsal store is unavailable.');
        }
        final previous = (await tx.loadHostState(grantsNamespace))[product];
        if (previous == PurchaseState.verified.name ||
            previous == PurchaseState.pending.name) {
          return;
        }
        await tx.saveHostValue(grantsNamespace, 'attempt:$product', _uuid.v4());
        await tx.saveHostValue(
          grantsNamespace,
          product,
          PurchaseState.pending.name,
        );
      });

  void _checkProduct(String product) {
    if (product != customProduct &&
        !templates.keys.any((key) => product == 'template:${key.$1}')) {
      throw ArgumentError('Unknown product.');
    }
  }

  Future<void> verifySimulatedOriginalPurchase() => repository.saveHostValue(
    grantsNamespace,
    'legacy',
    PurchaseState.verified.name,
  );

  List<ProfessionDraft> _decodeDrafts(Map<String, String> rows) => rows.values
      .map(
        (raw) =>
            ProfessionDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      )
      .toList();

  Future<List<ProfessionDraft>> drafts() async =>
      _decodeDrafts(await repository.loadHostState(draftsNamespace));

  Future<ProfessionDraft> begin(
    ProfessionKind kind, {
    TemplateVersion? recipe,
  }) => repository.transaction((tx) async {
    if (kind != ProfessionKind.standard) {
      _authorise(await _access(tx), kind, recipe?.id);
    }
    if ((kind == ProfessionKind.template) != (recipe != null)) {
      throw ArgumentError('Choose a template.');
    }
    final selected = recipe == null
        ? null
        : templates[(recipe.id, recipe.version)];
    if (recipe != null && selected == null) {
      throw StateError('The recipe is unavailable.');
    }
    final id = _uuid.v4();
    final draft = ProfessionDraft(
      id: id,
      kind: kind,
      templateId: selected?.id,
      templateVersion: selected?.version,
      layout: LayoutDraft(
        LayoutRevision(
          collectionId: id,
          version: 1,
          fields: selected?.fields ?? cpdStandardFields(id),
          headings: selected?.headings ?? const [],
        ),
        maxActiveFields: cpdActiveFieldLimit,
      ),
      report: ReportSelection(),
    );
    await tx.saveHostValue(draftsNamespace, id, jsonEncode(draft.toJson()));
    return draft;
  });

  Future<ProfessionDraft> beginEdit(String collectionId) =>
      repository.transaction((tx) async {
        final collection = await tx.loadCollection(collectionId);
        if (collection == null || collection.deleted) {
          throw StateError('Profession unavailable.');
        }
        final layouts = await tx.loadLayouts(collectionId);
        final active = layouts.last;
        final kind = active.templateId == null
            ? ProfessionKind.custom
            : ProfessionKind.template;
        _authorise(await _access(tx), kind, active.templateId);
        final existing = _decodeDrafts(await tx.loadHostState(draftsNamespace));
        for (final draft in existing) {
          if (draft.editing == collectionId) return draft;
        }
        final draft = ProfessionDraft(
          id: _uuid.v4(),
          name: collection.label,
          kind: kind,
          layout: LayoutDraft(active, maxActiveFields: cpdActiveFieldLimit),
          report: await _report(tx, collectionId, active.version),
          editing: collectionId,
          templateId: active.templateId,
          templateVersion: active.templateVersion,
        );
        await tx.saveHostValue(
          draftsNamespace,
          draft.id,
          jsonEncode(draft.toJson()),
        );
        return draft;
      });

  Future<void> persist(ProfessionDraft draft) {
    final raw = jsonEncode(draft.toJson());
    return repository.transaction((tx) async {
      final previous = (await tx.loadHostState(draftsNamespace))[draft.id];
      if (previous == null) {
        return; // A late write cannot resurrect a completed draft.
      }
      final stored = ProfessionDraft.fromJson(
        jsonDecode(previous) as Map<String, dynamic>,
      );
      if (stored.editing != draft.editing ||
          stored.kind != draft.kind ||
          stored.templateId != draft.templateId ||
          stored.templateVersion != draft.templateVersion ||
          stored.layout.collectionId != draft.layout.collectionId ||
          stored.layout.baseVersion != draft.layout.baseVersion) {
        throw StateError('The draft identity changed.');
      }
      await tx.saveHostValue(draftsNamespace, draft.id, raw);
    });
  }

  Future<void> discard(String id) =>
      repository.transaction((tx) => tx.removeHostValue(draftsNamespace, id));

  TemplateVersion? recipeFor(ProfessionDraft draft) =>
      templates[(draft.templateId, draft.templateVersion)];

  SchemeReportRules? rulesFor(ProfessionDraft draft) =>
      reportRules[(draft.templateId, draft.templateVersion)];

  Future<LayoutRevision> supplied(ProfessionDraft draft) =>
      _supplied(repository, draft);

  Future<LayoutRevision> _supplied(
    SqliteRecordingRepository tx,
    ProfessionDraft draft,
  ) async {
    final recipe = recipeFor(draft);
    if (draft.editing case final collection?) {
      final history = await tx.loadLayouts(collection);
      if (recipe == null) return history.last;
      return history.firstWhere(
        (r) => r.templateId == recipe.id && r.templateVersion == recipe.version,
      );
    }
    return LayoutRevision(
      collectionId: draft.id,
      version: 1,
      fields: recipe?.fields ?? cpdStandardFields(draft.id),
      headings: recipe?.headings ?? const [],
    );
  }

  Future<NameProblem?> checkName(String name) => _checkName(repository, name);
  Future<NameProblem?> _checkName(
    SqliteRecordingRepository tx,
    String input,
  ) async {
    final name = cpdProfessionLabel(input).toLowerCase();
    if (name.isEmpty) return NameProblem.blank;
    for (final profession in await tx.loadCollections()) {
      if (profession.label.toLowerCase() == name) {
        return profession.deleted ? NameProblem.deleted : NameProblem.exists;
      }
    }
    return null;
  }

  Future<bool> canUseNameInTransaction(
    SqliteRecordingRepository tx,
    String name,
  ) async => await _checkName(tx, name) == null;

  /// Publish a purchased layout for future records on an existing profession.
  Future<LayoutRevision> applyOwnedTemplate(
    String collectionId,
    (String, int) templateKey, {
    required int expectedLayoutVersion,
  }) => repository.transaction((tx) async {
    final recipe = templates[templateKey];
    if (recipe == null ||
        !(await _permanentAccess(tx)).templates.contains(recipe.id)) {
      throw StateError('An owned profession template is required.');
    }
    final history = await tx.loadLayouts(collectionId);
    final active = history.last;
    if (active.version != expectedLayoutVersion || active.templateId != null) {
      throw StateError(
        'The profession layout changed or already uses a template.',
      );
    }
    final previousReport = await _report(tx, collectionId, active.version);
    final emptyDraft = jsonEncode(LayoutDraft(active).toJson());
    final editing = _decodeDrafts(
      await tx.loadHostState(draftsNamespace),
    ).where((draft) => draft.editing == collectionId);
    for (final draft in editing) {
      if (jsonEncode(draft.layout.toJson()) != emptyDraft ||
          jsonEncode(draft.report.toJson()) !=
              jsonEncode(previousReport.toJson())) {
        throw const PendingProfessionDraftException();
      }
      await tx.removeHostValue(draftsNamespace, draft.id);
    }
    final adoption = await _installRecipe(
      tx,
      collectionId,
      recipe,
      expectedVersion: expectedLayoutVersion,
    );
    await tx.saveHostValue(
      reportsNamespace,
      '$collectionId:${adoption.version}',
      '[]',
    );
    return adoption;
  });

  Future<LayoutRevision> _installRecipe(
    SqliteRecordingRepository tx,
    String collectionId,
    TemplateVersion recipe, {
    required int expectedVersion,
  }) async {
    cpdFieldBindings(recipe.fields);
    if (await tx.loadTemplate(recipe.id, recipe.version) == null) {
      await tx.saveTemplate(recipe, maxActiveFields: cpdActiveFieldLimit);
    }
    if (bundles[(recipe.id, recipe.version)] case final bundle?) {
      await const HistoricalCpdBundles().retain(tx, bundle);
    }
    return tx.applyTemplate(
      collectionId,
      recipe,
      expectedVersion: expectedVersion,
      maxActiveFields: cpdActiveFieldLimit,
    );
  }

  /// Historical records can be read even when the store cannot verify ownership.
  Future<bool> canAddToLayout(LayoutRevision layout) async =>
      layout.templateId == null ||
      (await evaluationStatus(layout.templateId!)).canCreate;

  Future<RecordingRecord> createActivity(
    String collectionId,
    Map<String, Object> values, {
    required int expectedLayoutVersion,
    Iterable<RecordingAttachment> newAttachments = const [],
    Map<String, Map<String, String>> addedOptions = const {},
  }) => repository.transaction((tx) async {
    final layout = (await tx.loadLayouts(collectionId)).last;
    final duration = cpdFieldBindings(layout.fields)['cpd.creditedDuration'];
    checkCpdCreditedDuration(values[duration]);
    final templateId = layout.templateId;
    final ledger = evaluationLedger;
    var owned = false;
    if (templateId != null) {
      owned = (await _permanentAccess(tx)).templates.contains(templateId);
      if (!owned && ledger == null) {
        throw StateError('Template access is required.');
      }
      if (!owned && !_knownTemplate(templateId)) {
        throw const TemplateAllowanceException();
      }
    }
    final version = addedOptions.isEmpty
        ? expectedLayoutVersion
        : await _saveActivityOptions(
            tx,
            collectionId,
            expectedLayoutVersion,
            addedOptions,
          );
    final record = await tx.createRecord(
      collectionId,
      values,
      expectedLayoutVersion: version,
      newAttachments: newAttachments,
    );
    if (templateId != null && ledger != null) {
      await ledger.accountCreated(tx, templateId, record.id, owned: owned);
    }
    return record;
  });

  Future<RecordingRecord> editActivity(
    RecordingRecord record,
    Map<String, Object?> changes, {
    required int expectedLayoutVersion,
    Iterable<RecordingAttachment> newAttachments = const [],
    Map<String, Map<String, String>> addedOptions = const {},
  }) {
    Future<RecordingRecord> update(SqliteRecordingRepository tx) async {
      final history = await tx.loadLayouts(record.collectionId);
      final fields = resolveFields(record.layoutVersion, history);
      final duration = cpdFieldBindings(fields)['cpd.creditedDuration'];
      checkCpdCreditedDuration(changes[duration]);
      return tx.updateValues(
        record.id,
        changes,
        expectedVersion: record.version,
        newAttachments: newAttachments,
      );
    }

    if (addedOptions.isEmpty) return update(repository);
    return repository.transaction((tx) async {
      await _saveActivityOptions(
        tx,
        record.collectionId,
        expectedLayoutVersion,
        addedOptions,
      );
      return update(tx);
    });
  }

  Future<int> _saveActivityOptions(
    SqliteRecordingRepository tx,
    String collectionId,
    int version,
    Map<String, Map<String, String>> options,
  ) async {
    final revision = await tx.addFieldOptions(
      collectionId,
      options,
      expectedLayoutVersion: version,
    );
    final report = await _report(tx, collectionId, version);
    await tx.saveHostValue(
      reportsNamespace,
      '$collectionId:${revision.version}',
      jsonEncode(report.toJson()),
    );
    return revision.version;
  }

  Future<SchemeReportRules> requireOwnedReport(LayoutRevision layout) async {
    final access = await this.access();
    final definition = reportRules[(layout.templateId, layout.templateVersion)];
    if (definition == null || !access.hasTemplateAccess(layout.templateId)) {
      throw StateError(
        'The specialised report needs verified template ownership.',
      );
    }
    return definition;
  }

  /// Phase 9 retains scheme reporting independently of recording allowance.
  /// Only a persisted layout can supply a historical report version.
  Future<void> requireHistoricalReport(LayoutRevision layout) async {
    if (!evaluationsEnabled) {
      await requireOwnedReport(layout);
      return;
    }
    final pin = (layout.templateId, layout.templateVersion);
    final saved = await repository.loadLayouts(layout.collectionId);
    if (pin.$1 == null ||
        !saved.any(
          (revision) =>
              revision.version == layout.version &&
              (revision.templateId, revision.templateVersion) == pin,
        )) {
      throw StateError('The historical report needs a stored template layout.');
    }
  }

  Future<ReportSelection> reportAt(String collectionId, int version) =>
      _report(repository, collectionId, version);

  Future<ReportSelection> _report(
    SqliteRecordingRepository tx,
    String id,
    int version,
  ) async {
    final raw = (await tx.loadHostState(reportsNamespace))['$id:$version'];
    return raw == null
        ? ReportSelection()
        : ReportSelection.fromJson(jsonDecode(raw) as List);
  }

  Future<String> commit(
    String requestId, {
    bool firstProfession = false,
    bool acceptIncomplete = false,
  }) => repository.transaction((tx) async {
    final receipt = (await tx.loadHostState(_receipts))[requestId];
    if (receipt != null) return receipt;
    final raw = (await tx.loadHostState(draftsNamespace))[requestId];
    if (raw == null) throw StateError('Draft unavailable.');
    final draft = ProfessionDraft.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final access = draft.kind == ProfessionKind.standard
        ? CreationAccess()
        : await _access(tx);
    _authorise(access, draft.kind, draft.templateId);
    final recipe = recipeFor(draft);
    final baseline = await _supplied(tx, draft);
    if (draft.editing == null) {
      final problem = await _checkName(tx, draft.name);
      if (problem != null) throw ProfessionNameException(problem);
    }
    checkCpdLayoutEdit(baseline.fields, draft.layout.fields);
    if (draft.kind == ProfessionKind.standard) {
      final actual = draft.layout.fields
          .map((field) => field.toJson())
          .toList();
      final defaults = baseline.fields.map((field) => field.toJson()).toList();
      if (jsonEncode(actual) != jsonEncode(defaults) ||
          draft.layout.headings.isNotEmpty ||
          draft.report.excluded.isNotEmpty ||
          draft.layout.includeExisting.isNotEmpty ||
          draft.layout.reinstated.isNotEmpty) {
        throw StateError('Standard CPD uses the supplied free layout.');
      }
    }

    final rules = rulesFor(draft);
    if (draft.kind == ProfessionKind.template &&
        (recipe == null || rules == null)) {
      throw StateError('Unknown template or report version.');
    }
    if (rules != null) {
      if (!access.canCustomiseFields) {
        checkTemplateArrangement(baseline, draft.layout, draft.report, rules);
      }
      if (!acceptIncomplete &&
          rules.assess(baseline, draft.layout, draft.report).incomplete) {
        throw StateError('An incomplete report needs explicit confirmation.');
      }
    }
    final reportFieldIds = {
      ...baseline.fields.map((field) => field.id),
      ...draft.layout.fields.map((field) => field.id),
    };
    if (draft.report.excluded.any((id) => !reportFieldIds.contains(id))) {
      throw StateError('Report selection has an unknown field.');
    }

    var report = draft.report;
    final String collectionId;
    final int revision;
    if (draft.editing case final editing?) {
      if (editing != draft.layout.collectionId) {
        throw StateError('Invalid draft collection.');
      }
      final saved = await tx.saveLayoutDraft(draft.layout);
      collectionId = editing;
      revision = saved.version;
    } else if (recipe == null) {
      final collection = await tx.createCollection(
        cpdProfessionLabel(draft.name),
        fields: draft.layout.fields,
        headings: draft.layout.headings,
        maxActiveFields: cpdActiveFieldLimit,
      );
      collectionId = collection.id;
      revision = collection.layoutVersion;
    } else {
      final collection = await tx.createCollection(
        cpdProfessionLabel(draft.name),
      );
      collectionId = collection.id;
      final adoption = await _installRecipe(
        tx,
        collectionId,
        recipe,
        expectedVersion: 1,
      );
      final ids = {
        for (final (index, field) in recipe.fields.indexed)
          field.id: adoption.fields[index].id,
      };
      final headingIds = {
        for (final (index, heading) in recipe.headings.indexed)
          heading.id: adoption.headings[index].id,
      };
      final saved = await tx.reviseLayout(
        collectionId,
        [
          for (final field in draft.layout.fields)
            field.reidentify(ids[field.id] ?? field.id),
        ],
        headings: [
          for (final heading in draft.layout.headings)
            SectionHeading(
              headingIds[heading.id] ?? heading.id,
              heading.label,
              beforeFieldId:
                  ids[heading.beforeFieldId] ?? heading.beforeFieldId,
            ),
        ],
        expectedVersion: adoption.version,
        maxActiveFields: cpdActiveFieldLimit,
      );
      revision = saved.version;
      report = draft.report.remap(ids);
      await tx.saveHostValue(
        reportsNamespace,
        '$collectionId:${adoption.version}',
        '[]',
      );
    }

    await tx.saveHostValue(
      reportsNamespace,
      '$collectionId:$revision',
      jsonEncode(report.toJson()),
    );
    await tx.saveHostValue(_receipts, requestId, collectionId);
    if (firstProfession && draft.editing == null) {
      final settings = await tx.loadHostState(_settings);
      if (settings['firstProfession'] == null) {
        await tx.saveHostValue(_settings, 'firstProfession', collectionId);
      }
    }
    await tx.removeHostValue(draftsNamespace, requestId);
    return collectionId;
  });

  void _authorise(
    CreationAccess access,
    ProfessionKind kind,
    String? template,
  ) {
    if (!access.allows(kind, template)) {
      throw StateError('This configuration needs verified access.');
    }
  }
}

class ProfessionNameException implements Exception {
  const ProfessionNameException(this.problem);
  final NameProblem problem;
}
