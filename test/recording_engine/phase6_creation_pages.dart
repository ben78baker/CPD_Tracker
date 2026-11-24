import 'dart:async';
import 'dart:convert';

import 'package:cpd_tracker/cpd_backup/profession_backup_page.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/template_evaluation.dart';
import 'package:cpd_tracker/recording_editor/edit_fields_page.dart';
import 'package:cpd_tracker/recording_editor/field_settings.dart';
import 'package:cpd_tracker/recording_editor/strings.dart';
import 'package:cpd_tracker/recording_editor/template_preview.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/template_review.dart';
import 'package:cpd_tracker/widgets/form_section_tile.dart';
import 'package:flutter/material.dart';

import 'phase5_fixtures.dart';
import 'phase7_rehearsal_pages.dart';
import 'phase9_evaluation_panel.dart';

class ProfessionCreationPage extends StatefulWidget {
  const ProfessionCreationPage({
    super.key,
    required this.store,
    required this.onCreated,
    this.first = false,
    this.onBack,
    this.phase7 = false,
    this.backups,
    this.onBackupConflict,
  });
  final ProfessionCreationStore store;
  final ValueChanged<String> onCreated;
  final bool first;
  final bool phase7;
  final ProfessionBackupActions? backups;
  final ValueChanged<CollectionImportResult>? onBackupConflict;
  final VoidCallback? onBack;

  @override
  State<ProfessionCreationPage> createState() => _ProfessionCreationPageState();
}

class _ProfessionCreationPageState extends State<ProfessionCreationPage> {
  late Future<List<ProfessionDraft>> _drafts = widget.store.drafts();
  bool _opening = false;

  void _refresh() {
    if (mounted) {
      setState(() {
        _drafts = widget.store.drafts();
      });
    }
  }

  Future<void> _choose(ProfessionKind kind) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (kind == ProfessionKind.template) {
        final reportLanguage = widget.phase7
            ? ReportLanguage.fromStored(
                (await widget.store.settings())['reportLocale'],
              )
            : ReportLanguage.app;
        if (!mounted) return;
        final chosen = await chooseNursingTemplate(
          context,
          widget.store,
          phase7: widget.phase7,
          reportLanguage: reportLanguage,
        );
        if (!mounted || chosen != true) return;
      }
      final recipe = kind == ProfessionKind.template ? nursingPilot : null;
      final access = kind == ProfessionKind.standard
          ? CreationAccess()
          : await widget.store.access();
      if (!mounted) return;
      if (!access.allows(kind, recipe?.id)) {
        final unlocked = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => RehearsalCheckout(
              store: widget.store,
              product: recipe == null
                  ? ProfessionCreationStore.customProduct
                  : 'template:${recipe.id}',
            ),
          ),
        );
        if (!mounted || unlocked != true) return;
      }
      final draft = await widget.store.begin(kind, recipe: recipe);
      if (mounted) await _resume(draft);
    } on Object {
      if (mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _resume(ProfessionDraft draft) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProfessionDraftPage(
          store: widget.store,
          draft: draft,
          first: widget.first,
        ),
      ),
    );
    if (!mounted) return;
    if (id != null) {
      widget.onCreated(id);
    } else {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) widget.onBack?.call();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: widget.onBack == null
              ? null
              : BackButton(onPressed: widget.onBack),
          title: Text(widget.first ? s.p6First : s.addProfession),
        ),
        body: BoundedList(
          children: [
            for (final (kind, title, summary, icon) in [
              (
                ProfessionKind.standard,
                s.p6Standard,
                s.p6StandardDetail,
                Icons.edit_note,
              ),
              (ProfessionKind.custom, s.p6Custom, s.p6CustomDetail, Icons.tune),
              (
                ProfessionKind.template,
                s.p6Templates,
                s.p6TemplateDetail,
                Icons.library_books_outlined,
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  button: true,
                  child: InkWell(
                    key: ValueKey('phase6-${kind.name}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: _opening ? null : () => _choose(kind),
                    child: FormSectionTile(
                      label: title,
                      icon: icon,
                      child: Row(
                        children: [
                          Expanded(child: Text(summary)),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.backups case final backups?)
              OutlinedButton.icon(
                icon: const Icon(Icons.settings_backup_restore),
                onPressed: _opening
                    ? null
                    : () async {
                        final result = await backups.open(
                          context,
                          widget.store,
                        );
                        if (mounted && result?.collection != null) {
                          if (result!.status == CollectionImportStatus.added) {
                            widget.onCreated(result.collection!.id);
                          } else {
                            widget.onBackupConflict?.call(result);
                          }
                        }
                      },
                label: Text(s.pbRestore),
              ),
            FutureBuilder(
              future: _drafts,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(s.editorSaveError);
                final drafts =
                    snapshot.data?.where((draft) => draft.editing == null) ??
                    const [];
                return DraftChoices(
                  drafts: drafts,
                  onResume: _resume,
                  onDiscard: (draft) async {
                    if (await editorConfirmation(
                      context,
                      s.p6Discard,
                      s.p6DraftHint,
                      s.p6Discard,
                    )) {
                      await widget.store.discard(draft.id);
                      _refresh();
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DraftChoices extends StatelessWidget {
  const DraftChoices({
    super.key,
    required this.drafts,
    required this.onResume,
    required this.onDiscard,
  });
  final Iterable<ProfessionDraft> drafts;
  final ValueChanged<ProfessionDraft> onResume;
  final ValueChanged<ProfessionDraft> onDiscard;

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final draft in drafts)
          ListTile(
            title: Text(
              draft.name.isEmpty
                  ? switch (draft.kind) {
                      ProfessionKind.standard => s.p6Standard,
                      ProfessionKind.custom => s.p6Custom,
                      ProfessionKind.template => s.p6Templates,
                    }
                  : draft.name,
            ),
            subtitle: Text(s.p6Resume),
            leading: const Icon(Icons.edit_note),
            onTap: () => onResume(draft),
            trailing: IconButton(
              tooltip: s.p6Discard,
              onPressed: () => onDiscard(draft),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }
}

Future<bool?> chooseNursingTemplate(
  BuildContext context,
  ProfessionCreationStore store, {
  required bool phase7,
  required ReportLanguage reportLanguage,
  bool existingProfession = false,
  bool alreadyApplied = false,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    builder: (_) => _PilotCatalogue(
      store: store,
      phase7: phase7,
      reportLanguage: reportLanguage,
      existingProfession: existingProfession,
      alreadyApplied: alreadyApplied,
    ),
  ),
);

class _PilotCatalogue extends StatefulWidget {
  const _PilotCatalogue({
    required this.store,
    required this.phase7,
    required this.reportLanguage,
    required this.existingProfession,
    required this.alreadyApplied,
  });
  final ProfessionCreationStore store;
  final ReportLanguage reportLanguage;
  final bool phase7;
  final bool existingProfession, alreadyApplied;

  @override
  State<_PilotCatalogue> createState() => _PilotCatalogueState();
}

class _PilotCatalogueState extends State<_PilotCatalogue> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final language = Localizations.localeOf(context).toLanguageTag();
    final recipe = nursingPilot;
    return Scaffold(
      appBar: AppBar(title: Text(s.p6Templates)),
      body: BoundedList(
        children: [
          if (widget.store.evaluationsEnabled) Text(s.evaluationRehearsal),
          FormSectionTile(
            label: recipe.localizedLabel(language),
            icon: Icons.medical_services_outlined,
            supportingText: widget.phase7
                ? nursingBundle.label(
                    "description",
                    recipe.localizedDescription(language),
                    language,
                  )
                : recipe.localizedDescription(language),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.p6TemplateScope),
                if (widget.alreadyApplied) Text(s.appliedProfessionTemplate),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final chosen = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (previewContext) => nursingPilotPreview(
                          previewContext,
                          phase7: widget.phase7,
                          reportLanguage: widget.reportLanguage,
                          footer: widget.store.evaluationsEnabled
                              ? _evaluationPanel(previewContext)
                              : null,
                        ),
                      ),
                    );
                    if (!context.mounted) return;
                    if (chosen == true) {
                      Navigator.pop(context, true);
                    } else if (widget.store.evaluationsEnabled) {
                      setState(() => _revision++);
                    }
                  },
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(s.editorPreview),
                ),
                if (widget.store.evaluationsEnabled)
                  _evaluationPanel(context, key: ValueKey(_revision))
                else
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(s.p6ChooseTemplate),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _evaluationPanel(BuildContext context, {Key? key}) =>
      TemplateEvaluationPanel(
        key: key,
        store: widget.store,
        templateId: nursingPilot.id,
        ownedOnly: widget.existingProfession,
        purchase: () =>
            openTemplateCheckout(context, widget.store, nursingPilot.id),
        onUse: widget.alreadyApplied
            ? null
            : () => Navigator.pop(context, true),
      );
}

Future<void> openTemplateCheckout(
  BuildContext context,
  ProfessionCreationStore store,
  String templateId,
) async {
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          RehearsalCheckout(store: store, product: 'template:$templateId'),
    ),
  );
}

TemplatePreviewPage nursingPilotPreview(
  BuildContext context, {
  bool phase7 = false,
  ReportLanguage reportLanguage = ReportLanguage.app,
  Widget? footer,
}) {
  final s = editorStrings(context);
  final base = nursingPilot;
  final recipe = !phase7
      ? base
      : TemplateVersion(
          id: base.id,
          version: base.version,
          origin: base.origin,
          label: base.label,
          translations: base.translations,
          description: base.description,
          descriptionTranslations: nursingBundle.labels['description']!,
          fields: previewFields(nursingBundle),
          headings: base.headings,
        );
  final layout = LayoutRevision(
    collectionId: 'sample-arrangement',
    version: 1,
    fields: recipe.fields,
    headings: recipe.headings,
    templateId: recipe.id,
    templateVersion: recipe.version,
  );
  return TemplatePreviewPage(
    footer: footer,
    template: recipe,
    profession: nursingBundle.profession,
    country: nursingBundle.country,
    professionalBody: nursingBundle.body,
    scheme: nursingBundle.scheme,
    reviewed: DateTime.parse(nursingBundle.reviewed),
    featuresAndLimits: [
      s.p6TemplateScope,
      if (phase7)
        nursingBundle.label('scope', s.p7ReportScope, s.localeName)
      else
        'Activity totals distinguish participatory minutes. Official reflective accounts and confirmation are separate.',
    ],
    examples: phase7
        ? nursingBundle.examples.map(
            (sample) => TemplatePreviewExample(sample.title, sample.values),
          )
        : nursingExamples(recipe),
    sampleAttachmentLabel: 'Synthetic activity evidence',
    onReportError: phase7 ? rehearsalReportError : null,
    sampleReport: (template, _) async {
      if (!phase7) return nursingSampleReport(template, ReportSelection());
      final locale = await ReportLocale.resolve(reportLanguage, s);
      return exampleSchemeReport(locale);
    },
    arrangementPreview: (_) => EditFieldsPage(
      title: s.p6TryArrangement,
      layout: layout,
      library: phase5Library,
      maxActiveFields: cpdActiveFieldLimit,
      protectedDefinitionIds: cpdFieldKinds.keys.toSet(),
      suppliedLayout: layout,
      arrangementOnly: true,
      save: (draft, _) async {
        checkTemplateArrangement(
          layout,
          draft,
          ReportSelection(),
          nursingReportRules,
        );
        return layout.collectionId;
      },
    ),
  );
}

class RehearsalCheckout extends StatefulWidget {
  const RehearsalCheckout({
    super.key,
    required this.store,
    required this.product,
  });
  final ProfessionCreationStore store;
  final String product;
  @override
  State<RehearsalCheckout> createState() => _RehearsalCheckoutState();
}

class _RehearsalCheckoutState extends State<RehearsalCheckout> {
  late Future<
    (CreationAccess, Map<String, String>, bool, TemplateEvaluationStatus?)
  >
  _data = _read();
  bool _busy = false;

  Future<(CreationAccess, Map<String, String>, bool, TemplateEvaluationStatus?)>
  _read() async => (
    await widget.store.access(),
    await widget.store.purchaseStates(),
    (await widget.store.settings())['offline'] == 'true',
    widget.store.evaluationsEnabled && widget.product.startsWith('template:')
        ? await widget.store.evaluationStatus(widget.product.substring(9))
        : null,
  );

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _data = _read();
      });
    } on Object {
      if (mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final custom = widget.product == ProfessionCreationStore.customProduct;
    return Scaffold(
      appBar: AppBar(title: Text(s.p6Store)),
      body: FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(s.editorSaveError));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (access, ledger, offline, evaluation) = snapshot.requireData;
          final state = ledger[widget.product];
          final attempt = ledger['attempt:${widget.product}'];
          final owned = custom
              ? access.canCustomiseFields
              : access.templates.contains(widget.product.substring(9));
          final pending = state == PurchaseState.pending.name;
          return BoundedList(
            children: [
              FormSectionTile(
                label: custom ? s.p6Custom : s.p6Templates,
                icon: Icons.storefront_outlined,
                supportingText: s.p6StoreHint,
                child: Text(custom ? s.p6CustomScope : s.p6TemplateScope),
              ),
              if (evaluation != null)
                EvaluationSummary(evaluation, explain: true),
              SwitchListTile(
                title: Text(s.p6UseOffline),
                value: offline,
                onChanged: _busy
                    ? null
                    : (value) => _change(
                        () => widget.store.saveSetting(
                          'offline',
                          value.toString(),
                        ),
                      ),
              ),
              if (offline) Text(s.p6Offline),
              if (pending)
                Semantics(liveRegion: true, child: Text(s.p6Pending)),
              if (state == PurchaseState.cancelled.name) Text(s.p6Cancelled),
              if (owned) ...[
                Text(s.p6Owned),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(s.continueLabel),
                ),
              ] else ...[
                if (pending) ...[
                  FilledButton(
                    onPressed: offline || _busy
                        ? null
                        : () => _change(
                            () => widget.store.acceptSimulatedPurchase(
                              widget.product,
                              PurchaseState.verified,
                              attempt: attempt,
                            ),
                          ),
                    child: Text(s.p6Complete),
                  ),
                  TextButton(
                    onPressed: offline || _busy
                        ? null
                        : () => _change(
                            () => widget.store.acceptSimulatedPurchase(
                              widget.product,
                              PurchaseState.cancelled,
                              attempt: attempt,
                            ),
                          ),
                    child: Text(s.p6CancelPurchase),
                  ),
                ] else
                  FilledButton(
                    onPressed: offline || _busy
                        ? null
                        : () => _change(
                            () => widget.store.startSimulatedPurchase(
                              widget.product,
                            ),
                          ),
                    child: Text(s.p6Checkout),
                  ),
                OutlinedButton(
                  onPressed: offline || _busy
                      ? null
                      : () => _change(
                          () => widget.store.acceptSimulatedPurchase(
                            widget.product,
                            PurchaseState.verified,
                          ),
                        ),
                  child: Text(s.p6Restore),
                ),
                if (custom)
                  TextButton(
                    onPressed: offline || _busy
                        ? null
                        : () => _change(
                            widget.store.verifySimulatedOriginalPurchase,
                          ),
                    child: Text(s.p6Legacy),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class ProfessionDraftPage extends StatefulWidget {
  const ProfessionDraftPage({
    super.key,
    required this.store,
    required this.draft,
    this.first = false,
  });
  final ProfessionCreationStore store;
  final ProfessionDraft draft;
  final bool first;

  @override
  State<ProfessionDraftPage> createState() => _ProfessionDraftPageState();
}

typedef _DraftContext = ({
  LayoutRevision baseline,
  LayoutRevision published,
  CreationAccess access,
  Set<String> knownFields,
  Set<String> fieldsWithValues,
  ReportSelection report,
});

class _ProfessionDraftPageState extends State<ProfessionDraftPage> {
  late ProfessionDraft _draft = widget.draft;
  late final _name = TextEditingController(text: _draft.name);
  late final _context = _load();
  String? _problem;
  bool _busy = false;

  Future<_DraftContext> _load() async {
    final store = widget.store;
    final baseline = await store.supplied(_draft);
    final access = _draft.kind == ProfessionKind.standard
        ? CreationAccess()
        : await store.access();
    final collection = _draft.editing;
    final history = collection == null
        ? [baseline]
        : await store.repository.loadLayouts(collection);
    final published = history.last;
    return (
      baseline: baseline,
      published: published,
      access: access,
      knownFields: {
        for (final revision in history)
          ...revision.fields.map((field) => field.id),
      },
      fieldsWithValues: collection == null
          ? const <String>{}
          : await store.repository.fieldsWithValues(collection),
      report: collection == null
          ? ReportSelection()
          : await store.reportAt(collection, published.version),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _persist(ProfessionDraft draft) async {
    _draft = draft;
    try {
      await widget.store.persist(draft);
    } on Object {
      if (mounted) _showError(context);
      rethrow;
    }
  }

  void _autosave(ProfessionDraft draft) {
    unawaited(_persist(draft).catchError((Object _) {}));
  }

  Future<void> _edit(_DraftContext data) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<String>(builder: (_) => _editor(data)));
    if (mounted) setState(() {});
  }

  EditFieldsPage _editor(_DraftContext data) {
    final store = widget.store;
    final checkpoint = _draft;
    final editing = checkpoint.editing != null;
    final rules = store.rulesFor(checkpoint);
    final restricted = !data.access.canCustomiseFields;
    ProfessionDraft changed(LayoutDraft draft, Set<String> excluded) {
      final known = {
        ...data.knownFields,
        ...draft.fields.map((field) => field.id),
      };
      return checkpoint.withChanges(
        layout: draft,
        report: ReportSelection(excluded: excluded.where(known.contains)),
      );
    }

    return EditFieldsPage(
      title: checkpoint.name.isEmpty
          ? editorStrings(context).p6Layout
          : checkpoint.name,
      layout: data.published,
      initialDraft: checkpoint.layout,
      initiallyDirty:
          editing &&
          (jsonEncode(checkpoint.layout.toJson()) !=
                  jsonEncode(LayoutDraft(data.published).toJson()) ||
              jsonEncode(checkpoint.report.toJson()) !=
                  jsonEncode(data.report.toJson())),
      library: phase5Library,
      maxActiveFields: cpdActiveFieldLimit,
      protectedDefinitionIds: cpdFieldKinds.keys.toSet(),
      requiredReportDefinitions: rules?.requiredDefinitions ?? const {},
      arrangementOnly: restricted,
      suppliedLayout: rules == null ? null : data.baseline,
      reportExclusions: checkpoint.report.excluded,
      fieldsWithValues: data.fieldsWithValues,
      onDraftChanged: (draft, excluded) =>
          store.persist(changed(draft, excluded)),
      onCancel: editing
          ? () => store.discard(checkpoint.id)
          : () => store.persist(checkpoint),
      onReviewTemplate: editing && rules != null
          ? (_) => _reviewUpdate(data.baseline)
          : null,
      save: (draft, excluded) async {
        final updated = changed(draft, excluded);
        if (restricted && rules != null) {
          checkTemplateArrangement(data.baseline, draft, updated.report, rules);
        }
        if (editing) {
          await store.persist(updated);
          return store.commit(updated.id, acceptIncomplete: true);
        }
        await _persist(updated);
        return updated.layout.collectionId;
      },
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = editorStrings(context);
    if (!mounted) return;
    setState(() {
      _problem = null;
      _busy = true;
    });
    try {
      await _persist(_draft);
      final id = await widget.store.commit(
        _draft.id,
        firstProfession: widget.first,
      );
      if (mounted) Navigator.of(context).pop(id);
    } on ProfessionNameException catch (error) {
      if (mounted) {
        setState(
          () => _problem = switch (error.problem) {
            NameProblem.blank => s.pleaseEnterProfession,
            NameProblem.exists => s.professionAlreadyExists,
            NameProblem.deleted => s.professionInDeletedRestoreInstead,
          },
        );
      }
    } on Object {
      if (mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final s = editorStrings(context);
    if (!await editorConfirmation(
          context,
          s.p6Discard,
          s.p6DraftHint,
          s.p6Discard,
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.store.discard(_draft.id);
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewUpdate(LayoutRevision adoption) async {
    final original = widget.store.recipeFor(_draft)!;
    final proposed = TemplateVersion(
      id: original.id,
      version: original.version + 1,
      label: original.label,
      origin: original.origin,
      description: original.description,
      translations: original.translations,
      headings: original.headings,
      fields: [
        ...original.fields,
        LayoutField(
          id: 'nmc.demoObjective',
          definition: FieldDefinition(
            id: 'nmc.demoObjective',
            version: 1,
            label: 'Learning objective',
            kind: FieldKind.text,
          ),
        ),
      ],
    );
    final revisions = await widget.store.repository.loadLayouts(
      _draft.editing!,
    );
    final diff = TemplateReview.compare(
      original: original,
      adoption: adoption,
      installed: revisions.last,
      update: proposed,
    );
    if (!mounted) return;
    final s = editorStrings(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.p6TemplateUpdate),
        content: Text(
          '${s.editorVersion} ${original.version} → ${proposed.version} (synthetic candidate)\n\n'
          'New optional field: Learning objective\n'
          'Current local additions: ${diff.localFields.length}\n'
          'Current local removals: ${diff.removedLocally.length}\n'
          'The saved layout and report choices are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return FutureBuilder(
      future: _context,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(s.editorSaveError)),
          );
        }
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final access = data.access;
        final fieldAccess = access.allows(_draft.kind, _draft.templateId);
        if (_draft.editing != null) {
          if (fieldAccess) return _editor(data);
          return Scaffold(
            appBar: AppBar(title: Text(s.editFields)),
            body: Center(
              child: Text(
                _draft.kind == ProfessionKind.template
                    ? s.p6TemplateScope
                    : s.p6CustomScope,
              ),
            ),
          );
        }
        final rules = widget.store.rulesFor(_draft);
        final report = rules?.assess(
          data.baseline,
          _draft.layout,
          _draft.report,
        );
        return PopScope(
          canPop: !_busy,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.p6Create),
              actions: [
                IconButton(
                  tooltip: s.p6Discard,
                  onPressed: _busy ? null : _discard,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            body: BoundedList(
              children: [
                if (_draft.editing == null)
                  TextField(
                    key: const Key('phase6-name'),
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: s.p6Name,
                      errorText: _problem,
                    ),
                    onChanged: (name) {
                      setState(() => _problem = null);
                      _autosave(_draft.withChanges(name: name));
                    },
                  ),
                const SizedBox(height: 12),
                if (!fieldAccess)
                  Text(
                    _draft.kind == ProfessionKind.template
                        ? s.p6TemplateScope
                        : s.p6CustomScope,
                  )
                else if (_draft.kind != ProfessionKind.standard) ...[
                  OutlinedButton.icon(
                    onPressed: () => _edit(data),
                    icon: const Icon(Icons.tune),
                    label: Text(
                      access.canCustomiseFields ? s.editFields : s.p6Layout,
                    ),
                  ),
                  if (report != null) ...[
                    Text(
                      report.incomplete
                          ? s.p6Incomplete
                          : report.optionalChanges
                          ? s.p6Optional
                          : s.p6Compatible,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (report.incomplete) Text(_warning(report, context)),
                  ],
                ],
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: Text(
                        MaterialLocalizations.of(context).closeButtonLabel,
                      ),
                    ),
                    FilledButton(
                      key: const Key('phase6-commit'),
                      onPressed: _busy || !fieldAccess ? null : _save,
                      child: Text(s.p6Create),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _warning(ReportCompatibility report, BuildContext context) {
  final s = editorStrings(context);
  final language = Localizations.localeOf(context).toLanguageTag();
  return '${report.missing.map((f) => f.localizedLabel(language)).join(', ')}. ${s.p6CompatibilityHint}';
}

void _showError(BuildContext context) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(editorStrings(context).editorSaveError)));
