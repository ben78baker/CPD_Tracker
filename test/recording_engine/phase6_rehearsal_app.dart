import 'dart:async';
import 'dart:io';

import 'package:cpd_tracker/cpd_backup/profession_backup_page.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_records_source.dart';
import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_compatibility/sqlite_cpd_store.dart';
import 'package:cpd_tracker/cpd_records_page.dart';
import 'package:cpd_tracker/deleted_records_page.dart';
import 'package:cpd_tracker/global_search_page.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_data_store.dart'
    show cpdProfessionLabel;
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/template_evaluation.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/onboarding_page.dart';
import 'package:cpd_tracker/recording_editor/field_settings.dart'
    show editorConfirmation;
import 'package:cpd_tracker/recording_editor/record_form.dart';
import 'package:cpd_tracker/recording_editor/strings.dart';
import 'package:cpd_tracker/recording_editor/template_preview.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/record_export.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/settings_page.dart' show WeekStartSettingsRow;
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:cpd_tracker/widgets/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import 'phase6_creation_pages.dart';
import 'phase7_rehearsal_pages.dart';
import 'phase9_record_tools.dart';
import 'phase9_evaluation_panel.dart';

ProfessionCreationStore phase6Store(
  SqliteRecordingRepository repository, {
  TemplateEvaluationLedger? evaluationLedger,
}) => ProfessionCreationStore(
  repository,
  templates: {(nursingPilot.id, 1): nursingPilot},
  reportRules: {(nursingPilot.id, 1): nursingReportRules},
  bundles: {(nursingPilot.id, 1): nursingBundle},
  evaluationLedger: evaluationLedger,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    Phase6App(
      open: () async {
        final support = await getApplicationSupportDirectory();
        final root = Directory(p.join(support.path, 'phase6_rehearsal'));
        await root.create(recursive: true);
        return phase6Store(
          await SqliteRecordingRepository.open(
            p.join(root.path, 'sandbox.sqlite'),
          ),
        );
      },
    ),
  );
}

class Phase6App extends StatefulWidget {
  const Phase6App({
    super.key,
    required this.open,
    this.phase7 = false,
    this.originals,
    this.backups,
  });
  final ProfessionBackupActions? backups;
  final bool phase7;
  final ManagedAttachmentFiles? originals;
  final Future<ProfessionCreationStore> Function() open;
  @override
  State<Phase6App> createState() => _Phase6AppState();
}

class _Phase6AppState extends State<Phase6App> {
  final _locale = ValueNotifier<Locale?>(null);
  final _accent = ValueNotifier<AppAccent>(AppAccent.purple);
  late Future<ProfessionCreationStore> _opening = _open();

  Future<ProfessionCreationStore> _open() async {
    if (widget.phase7) await initializeDateFormatting();
    final store = await widget.open();
    final settings = await store.settings();
    final code = settings['locale'];
    const override = String.fromEnvironment('PHASE6_LOCALE');
    _locale.value = override.isNotEmpty
        ? Locale(override)
        : code == null || code.isEmpty
        ? null
        : Locale(code);
    _accent.value = AppAccent.fromStorage(settings['accent']);
    return store;
  }

  @override
  void dispose() {
    _locale.dispose();
    _accent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _locale,
    builder: (_, locale, _) => ValueListenableBuilder(
      valueListenable: _accent,
      builder: (_, accent, _) => MaterialApp(
        title: widget.phase7
            ? 'CPD · Phase 7 rehearsal'
            : 'CPD · Phase 6 rehearsal',
        locale: locale,
        theme: AppTheme.forAccent(accent),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        debugShowCheckedModeBanner: false,
        home: FutureBuilder(
          future: _opening,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return RetryPage(
                retry: () => setState(() {
                  _opening = _open();
                }),
              );
            }
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return _Launch(
              store: snapshot.requireData,
              locale: _locale,
              accent: _accent,
              phase7: widget.phase7,
              originals: widget.originals,
              backups: widget.backups,
            );
          },
        ),
      ),
    ),
  );
}

class _Launch extends StatefulWidget {
  const _Launch({
    required this.store,
    required this.locale,
    required this.accent,
    required this.phase7,
    this.originals,
    this.backups,
  });
  final ProfessionBackupActions? backups;
  final bool phase7;
  final ManagedAttachmentFiles? originals;
  final ProfessionCreationStore store;
  final ValueNotifier<Locale?> locale;
  final ValueNotifier<AppAccent> accent;

  @override
  State<_Launch> createState() => _LaunchState();
}

class _LaunchState extends State<_Launch> {
  late Future<(CreationStartup, Map<String, String>)> _state = _load();

  Future<(CreationStartup, Map<String, String>)> _load() async =>
      (await widget.store.startup(), await widget.store.settings());

  void _reload() => setState(() {
    _state = _load();
  });
  void _show(CreationStartup state) => setState(() {
    _state = widget.store.settings().then((saved) => (state, saved));
  });

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _state,
    builder: (context, snapshot) {
      if (snapshot.hasError) return RetryPage(retry: _reload);
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final (startup, saved) = snapshot.requireData;
      return switch (startup) {
        CreationStartup.welcome => OnboardingPage(
          preferences: OnboardingPreferences(
            locale: widget.locale,
            accent: widget.accent,
            initial: saved,
            showBackupHelp: widget.backups != null,
            save: widget.store.saveSetting,
            onContinue: () => _show(CreationStartup.resumeCreation),
          ),
        ),
        CreationStartup.resumeCreation => ProfessionCreationPage(
          first: true,
          backups: widget.backups,
          phase7: widget.phase7,
          store: widget.store,
          onBack: () => _show(CreationStartup.welcome),
          onCreated: (_) => _reload(),
        ),
        CreationStartup.home => _Home(
          store: widget.store,
          phase7: widget.phase7,
          originals: widget.originals,
          backups: widget.backups,
        ),
      };
    },
  );
}

class RetryPage extends StatelessWidget {
  const RetryPage({super.key, required this.retry});
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: BoundedList(
      children: [
        Text(editorStrings(context).editorSaveError),
        FilledButton(
          onPressed: retry,
          child: Text(editorStrings(context).continueLabel),
        ),
      ],
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home({
    required this.store,
    required this.phase7,
    this.originals,
    this.backups,
  });
  final ProfessionBackupActions? backups;
  final bool phase7;
  final ManagedAttachmentFiles? originals;
  final ProfessionCreationStore store;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late Future<List<RecordingCollection>> _professions = widget.store.repository
      .loadCollections();
  int _refreshToken = 0;
  void _refresh() {
    if (mounted) {
      setState(() {
        _refreshToken++;
        _professions = widget.store.repository.loadCollections();
      });
    }
  }

  bool get _integratedRecords =>
      widget.store.evaluationsEnabled && widget.originals != null;

  late final _source = SqliteCpdRecordsSource(
    widget.store.repository,
    widget.originals!,
    preferences: widget.store.settings,
    setReportLanguage: (language) =>
        widget.store.saveSetting('reportLocale', language.tag),
  );

  Future<void> _editFields(RecordingCollection profession) async {
    final store = widget.store;
    try {
      final active = (await store.repository.loadLayouts(profession.id)).last;
      bool canEdit(CreationAccess access) => active.templateId == null
          ? access.canCustomiseFields
          : access.hasTemplateAccess(active.templateId);
      final access = await store.access();
      if (!mounted) return;
      if (!canEdit(access)) {
        if (active.templateId case final template?) {
          await openTemplateCheckout(context, store, template);
        } else {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RehearsalCheckout(
                store: store,
                product: ProfessionCreationStore.customProduct,
              ),
            ),
          );
        }
        if (!canEdit(await store.access())) return;
      }
      final draft = await store.beginEdit(profession.id);
      if (!mounted) return;
      await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ProfessionDraftPage(store: store, draft: draft),
        ),
      );
      _refresh();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(editorStrings(context).editorSaveError)),
        );
      }
    }
  }

  Future<void> _professionTemplates(RecordingCollection profession) async {
    final store = widget.store;
    final s = editorStrings(context);
    try {
      final active = (await store.repository.loadLayouts(profession.id)).last;
      final settings = await store.settings();
      if (!mounted) return;
      final chosen = await chooseNursingTemplate(
        context,
        store,
        phase7: widget.phase7,
        reportLanguage: ReportLanguage.fromStored(settings['reportLocale']),
        existingProfession: true,
        alreadyApplied: active.templateId != null,
      );
      if (!mounted || chosen != true || active.templateId != null) return;
      final confirmed = await editorConfirmation(
        context,
        s.applyProfessionTemplate,
        '${profession.label}\n\n${s.applyProfessionTemplateHint}',
        s.applyProfessionTemplate,
      );
      if (!mounted || !confirmed) return;
      await store.applyOwnedTemplate(profession.id, (
        nursingPilot.id,
        nursingPilot.version,
      ), expectedLayoutVersion: active.version);
      _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PendingProfessionDraftException
                ? s.applyProfessionTemplatePending
                : s.recordChangeFailed,
          ),
        ),
      );
    }
  }

  Future<void> _openRecord(CpdRecordItem item, {required bool view}) =>
      RehearsalRecordPage.open(
        context,
        store: widget.store,
        professionId: item.professionId,
        recordId: item.id,
        view: view,
        originals: widget.originals,
        onEditFields: _editFields,
      );

  Future<void> _viewRecords(
    RecordingCollection profession, {
    bool search = false,
    String query = '',
  }) async {
    final repository = widget.store.repository;
    var layout = (await repository.loadLayouts(profession.id)).last;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (route, setRouteState) {
            final s = editorStrings(route);
            final custom =
                layout.templateId != null ||
                layout.version > 1 ||
                layout.fields.any(
                  (field) => !cpdFieldKinds.containsKey(field.definition.id),
                );
            return CpdRecordsPage(
              profession: profession.label,
              professionId: profession.id,
              source: _source,
              startInSearchMode: search,
              initialSearchQuery: query,
              onOpenRecord: _openRecord,
              onEditFields: () async {
                await _editFields(profession);
                final latest = (await repository.loadLayouts(
                  profession.id,
                )).last;
                if (route.mounted) setRouteState(() => layout = latest);
              },
              additionalFormats: {
                if (custom) 'custom_report': s.customFieldsReport,
                if (custom) 'field_csv': s.fieldValuesCsv,
                if (layout.templateId != null)
                  CpdRecordsPage.schemeReportFormat:
                      '${s.p6OpenReport} · ${s.p7Period}',
              },
              onAdditionalExport: (format, rows, language) =>
                  _exportRecording(profession, format, rows, language),
            );
          },
        ),
      ),
    );
    _refresh();
  }

  Future<void> _exportRecording(
    RecordingCollection profession,
    String format,
    List<CpdRecordItem> rows,
    ReportLanguage language,
  ) async {
    final store = widget.store;
    final (history, records) = await store.repository.transaction((tx) async {
      final history = await tx.loadLayouts(profession.id);
      final current = {
        for (final record in await tx.loadRecords(profession.id))
          record.id: record,
      };
      final selected = rows.map((row) {
        final record = current[row.id];
        if (record == null || record.version != row.version) {
          throw StateError('The export selection has changed.');
        }
        return record;
      }).toList();
      return (history, selected);
    });
    if (!mounted) return;
    if (format == CpdRecordsPage.schemeReportFormat) {
      await openSchemeReport(
        context,
        store,
        profession,
        history,
        records,
        history.last.version,
        originals: widget.originals,
        requireSavedPeriod: true,
        language: language,
      );
    } else if (format == 'field_csv') {
      await shareFieldValuesCsv(context, history, records);
    } else {
      final active = history.last;
      final report = await store.reportAt(profession.id, active.version);
      final beforeAdoption = history.where(
        (layout) => layout.templateId == null,
      );
      final previousReport =
          active.templateId != null && beforeAdoption.isNotEmpty
          ? await store.reportAt(profession.id, beforeAdoption.last.version)
          : null;
      final historicalExclusions = {
        if (previousReport != null)
          for (final revision in beforeAdoption)
            revision.version: previousReport.excluded,
      };
      if (!mounted) return;
      await openLayoutReport(
        context,
        store,
        profession,
        history,
        records,
        report.excluded,
        historicalExclusions: historicalExclusions,
        language: language,
        evidenceNames: {
          for (final row in rows)
            for (final asset in row.evidence) asset.id: asset.label,
        },
      );
    }
  }

  Future<void> _searchRecords() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GlobalSearchPage(
          source: _source,
          onOpenProfession: (item, query) async {
            final profession = await widget.store.repository.loadCollection(
              item.id,
            );
            if (mounted && profession != null && !profession.deleted) {
              await _viewRecords(profession, query: query);
            }
          },
          onOpenRecord: (item) => _openRecord(item, view: true),
        ),
      ),
    );
    _refresh();
  }

  Future<void> _showEvaluation(String templateId) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TemplateEvaluationPanel(
          store: widget.store,
          templateId: templateId,
          purchase: () => openTemplateCheckout(sheet, widget.store, templateId),
          onStandard: () async {
            Navigator.pop(sheet);
            final draft = await widget.store.begin(ProfessionKind.standard);
            if (!mounted) return;
            await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) =>
                    ProfessionDraftPage(store: widget.store, draft: draft),
              ),
            );
            _refresh();
          },
        ),
      ),
    ),
  );

  Future<void> _open(
    RecordingCollection profession, {
    bool add = false,
    bool search = false,
  }) async {
    if (add) {
      final history = await widget.store.repository.loadLayouts(profession.id);
      final enabled = await widget.store.canAddToLayout(history.last);
      if (!mounted) return;
      if (!enabled) {
        if (_integratedRecords && history.last.templateId != null) {
          await _showEvaluation(history.last.templateId!);
        } else if (widget.store.evaluationsEnabled) {
          await _open(profession);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(editorStrings(context).pbPremiumLocked)),
          );
        }
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RehearsalRecordPage(
            store: widget.store,
            collection: profession.id,
            history: history,
            phase7: true,
            originals: widget.originals,
          ),
        ),
      );
    } else if (_integratedRecords) {
      await _viewRecords(profession, search: search);
      return;
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ProfessionPage(
            store: widget.store,
            profession: profession,
            phase7: true,
            search: search,
            originals: widget.originals,
          ),
        ),
      );
    }
    _refresh();
  }

  Future<void> _manage(
    RecordingCollection profession, {
    bool delete = false,
  }) async {
    final s = editorStrings(context);
    var draft = profession.label;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(delete ? s.deleteProfessionTitle : s.renameProfessionTitle),
        content: delete
            ? Text(s.removeProfessionConfirm(profession.label))
            : TextFormField(
                initialValue: draft,
                onChanged: (value) => draft = value,
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(delete ? s.deleteProfession : s.save),
          ),
        ],
      ),
    );
    if (answer != true || !mounted) return;
    if (!delete &&
        (draft.trim() == profession.label ||
            await widget.store.checkName(draft) != null)) {
      return;
    }
    if (delete) {
      await widget.store.repository.updateCollection(
        profession.id,
        deleted: true,
      );
    } else {
      await SqliteCpdStore.renameCollectionWithTarget(
        widget.store.repository,
        profession,
        cpdProfessionLabel(draft),
      );
    }
    _refresh();
  }

  Future<void> _addProfession() async {
    CollectionImportResult? conflict;
    await Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (context) => ProfessionCreationPage(
          store: widget.store,
          phase7: widget.phase7,
          backups: widget.backups,
          onCreated: (id) => Navigator.pop(context, id),
          onBackupConflict: (result) {
            conflict = result;
            Navigator.pop(context);
          },
        ),
      ),
    );
    _refresh();
    final existing = conflict;
    if (!mounted || existing == null) return;
    if (existing.status == CollectionImportStatus.existing) {
      await _open(existing.collection!);
    } else {
      await _deletedProfessions();
    }
  }

  Future<void> _deletedProfessions() async {
    final all = await widget.store.repository.loadCollections();
    final deleted = all.where((item) => item.deleted).toList();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          final s = editorStrings(context);
          return Scaffold(
            appBar: AppBar(title: Text(s.deletedProfessionsTitle)),
            body: BoundedList(
              children: [
                if (deleted.isEmpty) Text(s.noDeletedProfessions),
                for (final item in deleted)
                  ListTile(
                    title: Text(item.label),
                    trailing: TextButton(
                      onPressed: () async {
                        await widget.store.repository.updateCollection(
                          item.id,
                          deleted: false,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(s.restore),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    _refresh();
  }

  Future<void> _chooseSearchProfession() async {
    final active = (await _professions).where(
      (profession) => !profession.deleted,
    );
    if (!mounted) return;
    final selection = await showModalBottomSheet<RecordingCollection>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final profession in active)
              ListTile(
                title: Text(profession.label),
                leading: const Icon(Icons.search),
                onTap: () => Navigator.pop(context, profession),
              ),
          ],
        ),
      ),
    );
    if (mounted && selection != null) await _open(selection, search: true);
  }

  void _rehearsalAction() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(editorStrings(context).p7Internal)));
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final body = FutureBuilder(
      future: _professions,
      builder: (context, snapshot) {
        if (snapshot.hasError) return RetryPage(retry: _refresh);
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final active = snapshot.requireData
            .where((profession) => !profession.deleted)
            .toList();
        if (widget.phase7) {
          return HomeProfessionList(
            itemCount: active.length,
            itemBuilder: (context, index) {
              final profession = active[index];
              return RehearsalProfessionCard(
                key: ValueKey(profession.id),
                store: widget.store,
                profession: profession,
                originals: widget.originals,
                onRefresh: _refresh,
                refreshToken: _refreshToken,
                onCreateBackup: widget.backups == null
                    ? null
                    : () => widget.backups!.open(
                        context,
                        widget.store,
                        collectionId: profession.id,
                      ),
                onEditFields: _integratedRecords
                    ? () => _editFields(profession)
                    : null,
                onTemplates: _integratedRecords
                    ? () => _professionTemplates(profession)
                    : null,
                onAdd: () => _open(profession, add: true),
                onView: () => _open(profession),
                onSearch: () => _open(profession, search: true),
                onScan: _rehearsalAction,
                onRename: () => _manage(profession),
                onDelete: () => _manage(profession, delete: true),
              );
            },
          );
        }
        return BoundedList(
          children: [
            FilledButton.icon(
              key: const Key('phase6-home-add'),
              icon: const Icon(Icons.add),
              label: Text(s.addProfession),
              onPressed: _addProfession,
            ),
            const SizedBox(height: 12),
            for (final profession in active)
              ListTile(
                key: ValueKey(profession.id),
                title: Text(profession.label),
                leading: const Icon(Icons.work_outline),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ProfessionPage(
                      store: widget.store,
                      profession: profession,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    return widget.phase7
        ? HomeShell(
            onSearch: _integratedRecords
                ? _searchRecords
                : _chooseSearchProfession,
            onMenuSelected: (action) {
              if (action == 'add_profession') {
                _addProfession();
              } else if (action == 'deleted_records' && _integratedRecords) {
                Navigator.of(context)
                    .push<void>(
                      MaterialPageRoute(
                        builder: (_) => DeletedRecordsPage(source: _source),
                      ),
                    )
                    .then((_) => _refresh());
              } else if (action == 'view_deleted' && widget.backups != null) {
                _deletedProfessions();
              } else if (action == 'settings' && widget.backups != null) {
                Navigator.of(context)
                    .push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            title: Text(editorStrings(context).settings),
                          ),
                          body: BoundedList(
                            children: [
                              const WeekStartSettingsRow(),
                              Text(
                                editorStrings(context).p8Title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(editorStrings(context).pbHelp),
                            ],
                          ),
                        ),
                      ),
                    )
                    .then((_) => _refresh());
              } else {
                _rehearsalAction();
              }
            },
            body: body,
          )
        : Scaffold(
            appBar: AppBar(title: Text(s.appTitle)),
            body: body,
          );
  }
}

class _ProfessionPage extends StatefulWidget {
  const _ProfessionPage({
    required this.store,
    required this.profession,
    this.phase7 = false,
    this.search = false,
    this.originals,
  });
  final bool phase7, search;
  final ManagedAttachmentFiles? originals;
  final ProfessionCreationStore store;
  final RecordingCollection profession;
  @override
  State<_ProfessionPage> createState() => _ProfessionPageState();
}

class _ProfessionPageState extends State<_ProfessionPage> {
  String _query = "";
  bool? _withinAllowance;
  late Future<(List<LayoutRevision>, List<RecordingRecord>, CreationAccess)>
  _state = _load();
  Future<(List<LayoutRevision>, List<RecordingRecord>, CreationAccess)>
  _load() async => (
    await widget.store.repository.loadLayouts(widget.profession.id),
    await widget.store.repository.loadRecords(widget.profession.id),
    await widget.store.access(),
  );
  void _refresh() {
    if (mounted) {
      setState(() {
        _withinAllowance = null;
        _state = _load();
      });
    }
  }

  Future<void> _edit() async {
    try {
      final draft = await widget.store.beginEdit(widget.profession.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<String>(
          builder: (_) =>
              ProfessionDraftPage(store: widget.store, draft: draft),
        ),
      );
      _refresh();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(editorStrings(context).editorSaveError)),
        );
      }
    }
  }

  Future<void> _report(
    List<LayoutRevision> history,
    List<RecordingRecord> records,
    int version,
  ) async {
    if (widget.phase7) {
      await openSchemeReport(
        context,
        widget.store,
        widget.profession,
        history,
        records,
        version,
        originals: widget.originals,
      );
      return;
    }
    final revision = history.singleWhere((layout) => layout.version == version);
    final rules = await widget.store.requireOwnedReport(revision);
    final original = history.firstWhere(
      (layout) =>
          layout.templateId == revision.templateId &&
          layout.templateVersion == revision.templateVersion,
    );
    final excluded = await widget.store.reportAt(widget.profession.id, version);
    final evidenceNames = <String, String>{};
    final evidenceIds = {
      for (final layout in history)
        for (final field in layout.fields)
          if (field.definition.kind == FieldKind.attachments) field.id,
    };
    for (final record in records) {
      for (final id in evidenceIds) {
        if (record.values[id] case final List references) {
          for (final reference in references.cast<String>()) {
            final evidence = await widget.store.repository.loadAttachment(
              reference,
            );
            if (evidence?.kind == AttachmentKind.link) {
              evidenceNames[reference] = evidence!.name;
            }
          }
        }
      }
    }
    final readiness = rules.assess(original, LayoutDraft(revision), excluded);
    if (!mounted) return;
    final s = editorStrings(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(s.p6OpenReport)),
          body: PdfPreview(
            initialPageFormat: PdfPageFormat.a4,
            allowSharing: false,
            allowPrinting: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            useActions: false,
            build: (_) => buildNursingActivityReport(
              entries: records.map(
                (record) => PilotReportEntry(
                  resolveFields(record.layoutVersion, history),
                  record.values,
                ),
              ),
              selection: excluded,
              incompleteLayout: readiness.incomplete,
              recipeVersion: revision.templateVersion!,
              rules: rules,
              requiredBindings: {
                for (final field in original.fields.where(rules.needs))
                  field.definition.id: field.id,
              },
              evidenceNames: evidenceNames,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _standardReport(
    List<LayoutRevision> history,
    List<RecordingRecord> records,
  ) async {
    final selected = await widget.store.reportAt(
      widget.profession.id,
      history.last.version,
    );
    if (widget.phase7) {
      if (!mounted) return;
      try {
        await openLayoutReport(
          context,
          widget.store,
          widget.profession,
          history,
          records,
          selected.excluded,
        );
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(editorStrings(context).editorSaveError)),
          );
        }
      }
      return;
    }
    final rows = [
      for (final record in records)
        ...recordExportRows(
          record,
          resolveFields(
            record.layoutVersion,
            history,
          ).where((field) => !selected.excluded.contains(field.id)),
        ),
    ];
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(editorStrings(context).editorExport)),
          body: BoundedList(
            children: [
              for (final row in rows)
                ListTile(title: Text(row[4]), subtitle: Text(row.last)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _record(
    List<LayoutRevision> history, [
    RecordingRecord? record,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RehearsalRecordPage(
          store: widget.store,
          collection: widget.profession.id,
          history: history,
          record: record,
          phase7: widget.phase7,
          originals: widget.originals,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _standard() async {
    final draft = await widget.store.begin(ProfessionKind.standard);
    if (!mounted) return;
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProfessionDraftPage(store: widget.store, draft: draft),
      ),
    );
    if (created != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.profession.label)),
      body: FutureBuilder(
        future: _state,
        builder: (context, snapshot) {
          if (snapshot.hasError) return RetryPage(retry: _refresh);
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (history, records, access) = snapshot.requireData;
          final active = history.last;
          final templateId = active.templateId;
          final hasTemplate = access.hasTemplateAccess(templateId);
          final evaluationUi = widget.store.evaluationsEnabled;
          final historical =
              evaluationUi && templateId != null && records.isNotEmpty;
          return BoundedList(
            children: [
              if (evaluationUi && templateId != null)
                TemplateEvaluationPanel(
                  key: ObjectKey(_state),
                  store: widget.store,
                  templateId: templateId,
                  purchase: () =>
                      openTemplateCheckout(context, widget.store, templateId),
                  onStandard: _standard,
                  onStatus: (status) {
                    if (_withinAllowance != status.canCreate) {
                      setState(() => _withinAllowance = status.canCreate);
                    }
                  },
                ),
              if (templateId == null ||
                  (evaluationUi ? _withinAllowance == true : hasTemplate))
                FilledButton(
                  onPressed: () => _record(history),
                  child: Text(s.editorNewRecord),
                )
              else if (!evaluationUi)
                Text(s.pbPremiumLocked),
              if (hasTemplate ||
                  access.canCustomiseFields && active.templateId == null)
                OutlinedButton(onPressed: _edit, child: Text(s.editFields)),
              if (hasTemplate || historical)
                OutlinedButton(
                  onPressed: () => _report(history, records, active.version),
                  child: Text(
                    hasTemplate ? s.p6OpenReport : s.evaluationHistorical,
                  ),
                ),
              if (!hasTemplate || evaluationUi)
                OutlinedButton(
                  onPressed: () => _standardReport(history, records),
                  child: Text(s.editorExport),
                ),
              if (widget.search)
                TextField(
                  decoration: InputDecoration(labelText: s.editorSearch),
                  onChanged: (value) => setState(() => _query = value),
                ),
              for (final (index, record) in records.indexed)
                if (!widget.search ||
                    record.matches(
                      _query,
                      resolveFields(record.layoutVersion, history),
                    ))
                  ListTile(
                    title: Text(
                      widget.phase7
                          ? (record.values[cpdFieldBindings(
                                      resolveFields(
                                        record.layoutVersion,
                                        history,
                                      ),
                                    )['cpd.title']]
                                    as String? ??
                                '${s.editorExample} ${index + 1}')
                          : '${s.editorExample} ${index + 1}',
                    ),
                    onTap: () => _record(history, record),
                    trailing: !hasTemplate && !historical
                        ? null
                        : IconButton(
                            tooltip: s.p6OpenReport,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            onPressed: () => _report(history, [
                              record,
                            ], record.layoutVersion),
                          ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class RehearsalRecordPage extends StatefulWidget {
  static Future<void> open(
    BuildContext context, {
    required ProfessionCreationStore store,
    required String professionId,
    required String recordId,
    required bool view,
    ManagedAttachmentFiles? originals,
    Future<void> Function(RecordingCollection)? onEditFields,
  }) async {
    Future<
      ({
        RecordingCollection profession,
        RecordingRecord record,
        List<LayoutRevision> history,
      })?
    >
    read() => store.repository.transaction((tx) async {
      final profession = await tx.loadCollection(professionId);
      final record = await tx.loadRecord(recordId);
      if (profession == null ||
          profession.deleted ||
          record == null ||
          record.deleted ||
          record.collectionId != professionId) {
        return null;
      }
      final history = await tx.loadLayouts(professionId);
      return (profession: profession, record: record, history: history);
    });

    final initial = await read();
    if (!context.mounted) return;
    if (initial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editorStrings(context).recordChangeFailed)),
      );
      return;
    }
    var current = initial;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (route, setRouteState) {
            Future<void> refresh() async {
              final latest = await read();
              if (!route.mounted) return;
              if (latest == null) {
                Navigator.of(route).pop();
                return;
              }
              setRouteState(() => current = latest);
            }

            return RehearsalRecordPage(
              key: ValueKey((
                current.record.version,
                current.history.last.version,
              )),
              store: store,
              collection: professionId,
              history: current.history,
              record: current.record,
              phase7: true,
              originals: originals,
              readOnly: view,
              onEditFields: view && onEditFields != null
                  ? () async {
                      await onEditFields(current.profession);
                      if (route.mounted) await refresh();
                    }
                  : null,
              onEditRecord: view
                  ? () async {
                      await open(
                        route,
                        store: store,
                        professionId: professionId,
                        recordId: recordId,
                        view: false,
                        originals: originals,
                      );
                      if (route.mounted) await refresh();
                    }
                  : null,
            );
          },
        ),
      ),
    );
  }

  const RehearsalRecordPage({
    super.key,
    required this.store,
    required this.collection,
    required this.history,
    this.record,
    this.phase7 = false,
    this.originals,
    this.readOnly = false,
    this.onEditFields,
    this.onEditRecord,
  });
  final bool phase7;
  final bool readOnly;
  final Future<void> Function()? onEditFields;
  final Future<void> Function()? onEditRecord;
  final ProfessionCreationStore store;
  final String collection;
  final List<LayoutRevision> history;
  final RecordingRecord? record;
  final ManagedAttachmentFiles? originals;
  @override
  State<RehearsalRecordPage> createState() => _RehearsalRecordPageState();
}

class _RehearsalRecordPageState extends State<RehearsalRecordPage> {
  late final _version =
      widget.record?.layoutVersion ?? widget.history.last.version;
  late final _layout = widget.history.singleWhere(
    (layout) => layout.version == _version,
  );
  late final _scoped =
      widget.store.evaluationsEnabled && _layout.templateId != null;
  late bool _maySave = !_scoped || widget.record != null;
  int _allowanceRevision = 0;
  late final _fields = resolveFields(_version, widget.history);
  late final _display = () {
    if (!widget.phase7) return _fields;
    final layout = widget.history.firstWhere(
      (revision) => revision.version == _version,
    );
    final bundle = phase7Bundles[(layout.templateId, layout.templateVersion)];
    if (bundle == null) return _fields;
    final base = widget.history.firstWhere(
      (revision) =>
          revision.templateId == bundle.recipe.id &&
          revision.templateVersion == bundle.recipe.version,
    );
    final translated = {
      for (final (index, definition) in previewFields(bundle).indexed)
        base.fields[index].id: definition.definition,
    };
    return [
      for (final field in _fields)
        if (translated[field.id] case final definition?
            when definition.version == field.definition.version)
          LayoutField.fromJson({
            ...field.toJson(),
            'definition': definition.toJson(),
          })
        else
          field,
    ];
  }();
  late final _values = Map<String, Object>.of(
    widget.record?.values ?? initialFieldValues(_fields),
  );
  final _changes = <String, Object?>{};
  final _pendingOptions = <String, Map<String, String>>{};
  late final _activeFields = {
    for (final field in widget.history.last.fields) field.id: field,
  };

  bool _canSaveOption(LayoutField field) =>
      _activeFields[field.id]?.definition.allowCustomOptions == true;

  LayoutField _optionsForEditing(LayoutField field) {
    if (widget.readOnly || !field.definition.allowCustomOptions) return field;
    return field.reidentify(
      field.id,
      addedOptions: {
        ...field.addedOptions,
        ...?_activeFields[field.id]?.addedOptions,
        ...?_pendingOptions[field.id],
      },
    );
  }

  void _addCustomOption(LayoutField field, String label, bool save) {
    final id = save ? const Uuid().v4() : null;
    if (id != null) {
      (_pendingOptions[field.id] ??= {})[id] = label;
    }
    final choice = storeChoiceSelection((id: id, text: label));
    if (field.definition.kind == FieldKind.multipleChoices) {
      final existing = (_values[field.id] as List?) ?? const [];
      _edit(field.id, [
        ...existing.where((value) {
          final text = readChoiceSelection(value)?.text;
          return text == null || choiceLabelKey(text) != choiceLabelKey(label);
        }),
        choice,
      ]);
    } else {
      _edit(field.id, choice);
    }
  }

  final _sampleEvidence = const Uuid().v4();
  late final _recordFiles = RehearsalRecordFiles(
    widget.store.repository,
    widget.originals,
  );
  late final _labels = _recordFiles.loadLabels(_fields, _values);
  bool _busy = false;
  bool _openingEditor = false;

  Future<void> _editRecord() async {
    if (_openingEditor) return;
    setState(() => _openingEditor = true);
    try {
      await widget.onEditRecord!();
    } finally {
      if (mounted) setState(() => _openingEditor = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _recordFiles.picking) return;
    final s = editorStrings(context);
    setState(() => _busy = true);
    try {
      final canonical = cpdFieldBindings(_fields);
      final title = _values[canonical['cpd.title']] as String?;
      final details = _values[canonical['cpd.details']] as String?;
      if ((title?.trim().isEmpty ?? true) &&
          (details?.trim().isEmpty ?? true)) {
        throw ArgumentError('No activity text.');
      }
      final date = _values[canonical['cpd.activityDate']];
      final now = DateTime.now();
      if (date is! String ||
          DateTime.parse(
            date,
          ).isAfter(DateTime(now.year, now.month, now.day))) {
        throw ArgumentError('A valid activity date is required.');
      }
      final attachments = <RecordingAttachment>[
        if (_values.values.whereType<List>().any(
          (ids) => ids.contains(_sampleEvidence),
        ))
          RecordingAttachment(
            id: _sampleEvidence,
            kind: AttachmentKind.link,
            locator: 'https://example.com/synthetic-evidence',
            name: s.editorSampleFile,
          ),
      ];
      final duration = canonical['cpd.creditedDuration']!;
      attachments.addAll(_recordFiles.linked(_fields, _values));
      if (widget.record case final record?) {
        if (_changes.containsKey(duration)) _changes[duration] ??= 0;
        await widget.store.editActivity(
          record,
          _changes,
          expectedLayoutVersion: widget.history.last.version,
          newAttachments: attachments,
          addedOptions: _pendingOptions,
        );
      } else {
        _values.putIfAbsent(duration, () => 0);
        await widget.store.createActivity(
          widget.collection,
          _values,
          expectedLayoutVersion: _version,
          newAttachments: attachments,
          addedOptions: _pendingOptions,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on TemplateAllowanceException {
      if (mounted) {
        setState(() {
          _maySave = false;
          _allowanceRevision++;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.evaluationSaveBlocked)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.editorBadRecord)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    if (widget.originals != null && widget.store.evaluationsEnabled) {
      unawaited(_recordFiles.dispose());
    }
    super.dispose();
  }

  Future<void> _addAttachment(LayoutField field) async {
    final attachment = await _recordFiles.pick(context, field);
    if (!mounted || attachment == null) return;
    _edit(field.id, [
      ...?(_values[field.id] as List?)?.cast<String>(),
      attachment,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final ids = widget.history.last.fields.map((f) => f.id).toSet();
    final old = _display.where((field) => !ids.contains(field.id)).toList();
    final realEvidence =
        widget.store.evaluationsEnabled && widget.originals != null;
    Widget form(List<LayoutField> fields, {bool historical = false}) =>
        FutureBuilder(
          future: realEvidence ? _labels : null,
          builder: (_, snapshot) => RecordingForm(
            fields: fields.map(_optionsForEditing).toList(),
            values: _values,
            readOnly: widget.readOnly,
            onCustomOption: widget.store.evaluationsEnabled && !widget.readOnly
                ? _addCustomOption
                : null,
            reusableOptionFields: {
              for (final field in fields)
                if (_canSaveOption(field)) field.id,
            },
            sampleAttachmentId: !realEvidence && !historical
                ? _sampleEvidence
                : null,
            attachmentLabels: {
              ...?snapshot.data,
              if (realEvidence) ..._recordFiles.pendingLabels,
            },
            addAttachment: realEvidence && !widget.readOnly
                ? _addAttachment
                : null,
            openAttachment: realEvidence
                ? (id) => _recordFiles.open(context, id)
                : null,
            onChanged: _busy || widget.readOnly ? null : _edit,
          ),
        );
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.readOnly
                ? s.viewRecord
                : widget.store.evaluationsEnabled
                ? (widget.record == null ? s.newEntry : s.editRecord)
                : (widget.record == null ? s.editorNewRecord : s.editorExample),
          ),
          actions: [
            if (widget.readOnly && widget.onEditFields != null)
              PopupMenuButton<String>(
                onSelected: (_) => widget.onEditFields!(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit_fields',
                    child: Text(s.editFields),
                  ),
                ],
              ),
          ],
        ),
        body: BoundedList(
          key: widget.readOnly ? const PageStorageKey('view-record') : null,
          children: [
            if (_scoped && !widget.readOnly)
              TemplateEvaluationPanel(
                key: ValueKey(_allowanceRevision),
                store: widget.store,
                templateId: _layout.templateId!,
                purchase: () => openTemplateCheckout(
                  context,
                  widget.store,
                  _layout.templateId!,
                ),
                onStatus: (status) => setState(() {
                  _maySave = widget.record != null || status.canCreate;
                }),
              ),
            form(_display.where((field) => ids.contains(field.id)).toList()),
            if (old.isNotEmpty) ...[
              Text(s.editorHistorical),
              form(old, historical: true),
            ],
          ],
        ),
        bottomNavigationBar:
            (widget.readOnly ? widget.onEditRecord != null : _maySave)
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: widget.readOnly
                      ? FilledButton.icon(
                          onPressed: _openingEditor ? null : _editRecord,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(s.editRecord),
                        )
                      : FilledButton(
                          onPressed: _busy ? null : _save,
                          child: Text(s.save),
                        ),
                ),
              )
            : null,
      ),
    );
  }

  void _edit(String id, Object? value) => setState(() {
    _changes[id] = value;
    if (value == null) {
      _values.remove(id);
    } else {
      _values[id] = value;
    }
  });
}
