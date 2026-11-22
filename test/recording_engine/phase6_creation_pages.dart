import 'dart:async';

import 'package:cpd_tracker/cpd_backup/profession_backup_page.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
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
import 'phase9_trial_panel.dart';

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
        final chosen = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => _PilotCatalogue(
              store: widget.store,
              phase7: widget.phase7,
              reportLanguage: reportLanguage,
            ),
          ),
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

class _PilotCatalogue extends StatefulWidget {
  const _PilotCatalogue({
    required this.store,
    required this.phase7,
    required this.reportLanguage,
  });
  final ProfessionCreationStore store;
  final ReportLanguage reportLanguage;
  final bool phase7;

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
          if (widget.store.trialsEnabled) Text(s.trialRehearsal),
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final chosen = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (previewContext) => nursingPilotPreview(
                          previewContext,
                          phase7: widget.phase7,
                          reportLanguage: widget.reportLanguage,
                          footer: widget.store.trialsEnabled
                              ? _trialPanel(previewContext)
                              : null,
                        ),
                      ),
                    );
                    if (!context.mounted) return;
                    if (chosen == true) {
                      Navigator.pop(context, true);
                    } else if (widget.store.trialsEnabled) {
                      setState(() => _revision++);
                    }
                  },
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(s.editorPreview),
                ),
                if (widget.store.trialsEnabled)
                  _trialPanel(context, key: ValueKey(_revision))
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

  Widget _trialPanel(BuildContext context, {Key? key}) => TemplateTrialPanel(
    key: key,
    store: widget.store,
    templateId: nursingPilot.id,
    purchase: () =>
        openTemplateCheckout(context, widget.store, nursingPilot.id),
    onUse: () => Navigator.pop(context, true),
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
      suppliedFields: recipe.fields,
      arrangementOnly: true,
      save: (draft) async {
        checkTemplateArrangement(
          layout,
          draft,
          ReportSelection(),
          nursingReportRules,
        );
        return layout;
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
  late Future<(CreationAccess, Map<String, String>, bool)> _data = _read();
  bool _busy = false;

  Future<(CreationAccess, Map<String, String>, bool)> _read() async => (
    await widget.store.access(),
    await widget.store.purchaseStates(),
    (await widget.store.settings())['offline'] == 'true',
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
          final (access, ledger, offline) = snapshot.requireData;
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

class _ProfessionDraftPageState extends State<ProfessionDraftPage> {
  late ProfessionDraft _draft = widget.draft;
  late final _name = TextEditingController(text: _draft.name);
  late final _context = _load();
  String? _problem;
  bool _busy = false;

  Future<(LayoutRevision, CreationAccess)> _load() async => (
    await widget.store.supplied(_draft),
    _draft.kind == ProfessionKind.standard
        ? CreationAccess()
        : await widget.store.access(),
  );

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

  Future<void> _edit(LayoutRevision baseline, CreationAccess access) async {
    final rules = widget.store.rulesFor(_draft);
    final restricted = !access.canCustomiseFields;
    final layout = LayoutRevision(
      collectionId: _draft.layout.collectionId,
      version: _draft.layout.baseVersion,
      fields: _draft.layout.fields,
      headings: _draft.layout.headings,
    );
    Future<void> keep(LayoutDraft draft) async {
      final ids = {
        ...baseline.fields.map((f) => f.id),
        ...draft.fields.map((f) => f.id),
      };
      await _persist(
        _draft.withChanges(
          layout: draft,
          report: ReportSelection(
            excluded: _draft.report.excluded.where(ids.contains),
          ),
        ),
      );
    }

    await Navigator.of(context).push(
      MaterialPageRoute<LayoutRevision>(
        builder: (_) => EditFieldsPage(
          title: _draft.name.isEmpty
              ? editorStrings(context).p6Layout
              : _draft.name,
          layout: layout,
          initialDraft: _draft.layout,
          library: phase5Library,
          maxActiveFields: cpdActiveFieldLimit,
          protectedDefinitionIds: cpdFieldKinds.keys.toSet(),
          arrangementOnly: restricted,
          suppliedFields: rules == null ? const [] : baseline.fields,
          onDraftChanged: keep,
          onExit: () => keep(_draft.layout),
          save: (draft) async {
            if (restricted && rules != null) {
              checkTemplateArrangement(baseline, draft, _draft.report, rules);
            }
            await keep(draft);
            return layout;
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _reset(LayoutRevision baseline) async {
    final s = editorStrings(context);
    if (!await editorConfirmation(
          context,
          s.p6RestoreDefaults,
          s.p6ResetHint,
          s.p6RestoreDefaults,
        ) ||
        !mounted) {
      return;
    }
    final draft = LayoutDraft(
      LayoutRevision(
        collectionId: _draft.layout.collectionId,
        version: _draft.layout.baseVersion,
        fields: const [],
      ),
      maxActiveFields: cpdActiveFieldLimit,
    );
    for (final field in baseline.fields) {
      draft.reinstate(field);
    }
    draft.setHeadings(baseline.headings);
    setState(
      () =>
          _draft = _draft.withChanges(layout: draft, report: ReportSelection()),
    );
    _autosave(_draft);
  }

  Future<void> _save(LayoutRevision baseline) async {
    if (_busy) return;
    final s = editorStrings(context);
    final compatibility = widget.store
        .rulesFor(_draft)
        ?.assess(baseline, _draft.layout, _draft.report);
    final accept = compatibility?.incomplete == true;
    if (accept &&
        !await editorConfirmation(
          context,
          s.p6Incomplete,
          _warning(compatibility!, context),
          s.save,
        )) {
      return;
    }
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
        acceptIncomplete: accept,
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
    } on TemplateAccessException {
      if (mounted) setState(() => _problem = s.trialSaveBlocked);
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
        final baseline = snapshot.data?.$1;
        final access = snapshot.data?.$2;
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(s.editorSaveError)),
          );
        }
        if (baseline == null || access == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final rules = widget.store.rulesFor(_draft);
        final report = rules?.assess(baseline, _draft.layout, _draft.report);
        final fieldAccess = access.allows(_draft.kind, _draft.templateId);
        final reportFields = {
          for (final field in baseline.fields) field.id: field,
          for (final field in _draft.layout.fields) field.id: field,
        };
        final language = Localizations.localeOf(context).toLanguageTag();
        return PopScope(
          canPop: !_busy,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_draft.editing == null ? s.p6Create : s.editFields),
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
                    onPressed: () => _edit(baseline, access),
                    icon: const Icon(Icons.tune),
                    label: Text(s.p6Layout),
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
                  const SizedBox(height: 12),
                  Text(
                    s.p6ReportFields,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(s.p6ReportHint),
                  for (final field in reportFields.values)
                    SwitchListTile(
                      title: Text(field.localizedLabel(language)),
                      value: !_draft.report.excluded.contains(field.id),
                      onChanged:
                          rules?.needs(field) == true &&
                              !access.canCustomiseFields
                          ? null
                          : (included) => setState(() {
                              final ids = {..._draft.report.excluded};
                              included
                                  ? ids.remove(field.id)
                                  : ids.add(field.id);
                              _autosave(
                                _draft.withChanges(
                                  report: ReportSelection(excluded: ids),
                                ),
                              );
                            }),
                    ),
                  if (rules != null)
                    TextButton.icon(
                      onPressed: () => _reset(baseline),
                      icon: const Icon(Icons.settings_backup_restore),
                      label: Text(s.p6RestoreDefaults),
                    ),
                ],
                if (_draft.editing != null && rules != null)
                  TextButton(
                    onPressed: () => _reviewUpdate(baseline),
                    child: Text(s.p6TemplateUpdate),
                  ),
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
                      onPressed: _busy || !fieldAccess
                          ? null
                          : () => _save(baseline),
                      child: Text(_draft.editing == null ? s.p6Create : s.save),
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
