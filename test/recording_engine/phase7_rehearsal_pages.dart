import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/historical_bundles.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_targets.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_period_store.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress_panel.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/recording_editor/strings.dart';
import 'package:cpd_tracker/recording_editor/template_preview.dart'
    show BoundedList;
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_reports/activity_document.dart';
import 'package:cpd_tracker/utils/cpd_pdf_document.dart'
    show CpdPdfFonts, loadCpdPdfFonts;
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/widgets/branded_headers.dart';
import 'package:cpd_tracker/widgets/form_section_tile.dart';
import 'package:cpd_tracker/widgets/profession_card.dart';
import 'package:cpd_tracker/widgets/report_language_tile.dart';
import 'package:cpd_tracker/widgets/tactile_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

final phase7Bundles = {
  (nursingBundle.recipe.id, nursingBundle.recipe.version): nursingBundle,
};

final rehearsalPeriod = SchemePeriod.create(
  nursingBundle,
  id: 'nmc-sample-2024',
  kind: PeriodKind.fixed,
  anchor: '2024-01-01',
  deadline: '2026-12-01',
);

/// Display translation overlay. Stored layout definitions and historical
/// choices retain their original meaning, identity and content.
List<LayoutField> previewFields(ProfessionTemplateBundle bundle) => [
  for (final field in bundle.recipe.fields)
    LayoutField.fromJson({
      ...field.toJson(),
      'definition': {
        ...field.definition.toJson(),
        'translations': {
          ...field.definition.translations,
          ...?bundle.labels[field.id],
        },
      },
    }),
];

Future<Uint8List> exampleSchemeReport(ReportLocale locale) async {
  final outputFonts = await _schemeFonts();
  return buildBundleExampleReport(
    bundle: nursingBundle,
    period: rehearsalPeriod,
    strings: locale.strings,
    reportLocale: locale,
    regular: outputFonts.regular,
    bold: outputFonts.bold,
  );
}

Future<CpdPdfFonts> _schemeFonts() => loadCpdPdfFonts().timeout(
  const Duration(seconds: 4),
  onTimeout: CpdPdfFonts.standard,
);

Widget rehearsalReportError(BuildContext context, Object error) => Center(
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Text(
      error is DevanagariPdfUnsupported
          ? editorStrings(context).reportHindiRequiresShaping
          : editorStrings(context).editorSaveError,
    ),
  ),
);

class RehearsalProfessionCard extends StatelessWidget {
  const RehearsalProfessionCard({
    super.key,
    required this.store,
    required this.profession,
    required this.onAdd,
    required this.onScan,
    required this.onView,
    required this.onSearch,
    required this.onRename,
    required this.onDelete,
    required this.onRefresh,
    this.originals,
    this.onCreateBackup,
  });

  final ProfessionCreationStore store;
  final RecordingCollection profession;
  final VoidCallback onAdd,
      onScan,
      onView,
      onSearch,
      onRename,
      onDelete,
      onRefresh;
  final ManagedAttachmentFiles? originals;
  final VoidCallback? onCreateBackup;

  Future<(ProfessionTemplateBundle?, SchemeProgress?, (int, String)?)>
  _load() async {
    final history = await store.repository.loadLayouts(profession.id);
    final active = history.last;
    final bundle = phase7Bundles[(active.templateId, active.templateVersion)];
    if (bundle == null) {
      final saved = (await store.repository.loadHostState(
        _standardTargets,
      ))[profession.id];
      final parts = saved?.split(':');
      final minutes = int.tryParse(parts?.first ?? '');
      return (
        null,
        null,
        parts == null || minutes == null ? null : (minutes, parts.last),
      );
    }
    final periods = await SchemePeriodStore(
      store.repository,
    ).load(profession.id);
    if (periods.selected == null) return (bundle, null, null);
    final selected = periods.periods.singleWhere(
      (period) => period.id == periods.selected,
    );
    final pinned =
        phase7Bundles[(selected.templateId, selected.templateVersion)]!;
    final result = await loadSchemeProgress(
      repository: store.repository,
      bundle: pinned,
      period: selected,
      history: history,
      records: await store.repository.loadRecords(profession.id),
      originals: originals,
    );
    return (pinned, result.progress, null);
  }

  static const _standardTargets = 'cpd.phase7.standard-targets';

  Future<int> _standardCompleted(String cycle) async {
    final history = await store.repository.loadLayouts(profession.id);
    final (start, end) = cpdTargetPeriod(DateTime.now(), cycle);
    final lower = schemeDay(start), upper = schemeDay(end);
    var total = 0;
    for (final record in await store.repository.loadRecords(profession.id)) {
      final bindings = cpdFieldBindings(
        resolveFields(record.layoutVersion, history),
      );
      final date = record.values[bindings['cpd.activityDate']] as String?;
      if (date != null &&
          date.compareTo(lower) >= 0 &&
          date.compareTo(upper) < 0) {
        total += record.values[bindings['cpd.creditedDuration']] as int? ?? 0;
      }
    }
    return total;
  }

  Future<void> _editStandardTarget(
    BuildContext context,
    (int, String)? current,
  ) async {
    final s = editorStrings(context);
    var cycle = current?.$2 ?? 'year';
    var minutes = current?.$1.toString() ?? '';
    final target = await showDialog<(int, String)>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.setEditTarget),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: cycle,
              onChanged: (value) => cycle = value!,
              items: [
                DropdownMenuItem(value: 'week', child: Text(s.perWeek)),
                DropdownMenuItem(value: 'month', child: Text(s.perMonth)),
                DropdownMenuItem(value: 'year', child: Text(s.perYear)),
              ],
            ),
            TextFormField(
              decoration: InputDecoration(labelText: s.minutesLabel),
              initialValue: minutes,
              keyboardType: TextInputType.number,
              onChanged: (value) => minutes = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(minutes);
              if (value != null && value > 0) {
                Navigator.pop(context, (value, cycle));
              }
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    if (target != null) {
      await store.repository.saveHostValue(
        _standardTargets,
        profession.id,
        '${target.$1}:${target.$2}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _load(),
    builder: (context, snapshot) {
      final s = editorStrings(context);
      final (bundle, progress, target) = snapshot.data ?? (null, null, null);
      void period() async {
        if (bundle == null) {
          await _editStandardTarget(context, target);
          onRefresh();
          return;
        }
        await pickSchemePeriod(context, store, profession, bundle);
        onRefresh();
      }

      if (snapshot.hasError) {
        return ListTile(
          title: Text(profession.label),
          subtitle: Text(s.editorSaveError),
          onTap: onView,
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return ProfessionCard(
        name: profession.label,
        onCreateBackup: onCreateBackup,
        onAdd: onAdd,
        onScan: onScan,
        onView: onView,
        onSearch: onSearch,
        onRename: onRename,
        onDelete: onDelete,
        target: target,
        computeCompleted: _standardCompleted,
        onSetTarget: period,
        refreshToken: 0,
        targetMenuLabel: bundle?.label('period', s.p7Period, s.localeName),
        progressContent: bundle == null
            ? null
            : SchemeProgressPanel(
                bundle: bundle,
                progress: progress,
                onPeriods: period,
              ),
      );
    },
  );
}

Future<void> pickSchemePeriod(
  BuildContext context,
  ProfessionCreationStore store,
  RecordingCollection profession,
  ProfessionTemplateBundle bundle,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _PeriodsPage(
      store: SchemePeriodStore(store.repository),
      collection: profession.id,
      bundle: bundle,
      access: store,
    ),
  ),
);

class _PeriodsPage extends StatefulWidget {
  const _PeriodsPage({
    required this.store,
    required this.collection,
    required this.bundle,
    required this.access,
  });
  final SchemePeriodStore store;
  final String collection;
  final ProfessionTemplateBundle bundle;
  final ProfessionCreationStore access;

  @override
  State<_PeriodsPage> createState() => _PeriodsPageState();
}

class _PeriodsPageState extends State<_PeriodsPage> {
  late final _periods = widget.store.load(widget.collection);
  late PeriodKind _kind = widget.bundle.periods.contains(PeriodKind.fixed)
      ? PeriodKind.fixed
      : widget.bundle.periods.first;
  DateTime? _anchor;
  DateTime? _end;
  DateTime? _deadline;
  bool _busy = false;
  bool _creating = false;

  Future<void> _select(SchemePeriod period) async {
    setState(() => _busy = true);
    try {
      await widget.store.select(
        widget.collection,
        period,
        canChange: (tx) =>
            widget.access.checkTrialTemplateAccess(tx, period.templateId),
      );
      if (mounted) Navigator.pop(context);
    } on TemplateAccessException {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(editorStrings(context).trialSaveBlocked)),
        );
      }
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(editorStrings(context).editorSaveError)),
        );
      }
    }
  }

  Future<void> _chooseDate({bool deadline = false}) async {
    final now = DateTime.now();
    final appLocale = Localizations.localeOf(context);
    final calendarLocale = appLocale.languageCode == 'en'
        ? const Locale('en', 'GB')
        : appLocale;
    final first = DateTime(1900);
    final last = DateTime(now.year + 30, 12, 31);
    if (!deadline && _kind == PeriodKind.custom) {
      final dates = await showDateRangePicker(
        context: context,
        locale: calendarLocale,
        firstDate: first,
        lastDate: last,
        initialDateRange: _anchor == null || _end == null
            ? null
            : DateTimeRange(start: _anchor!, end: _end!),
      );
      if (mounted && dates != null) {
        setState(() {
          _anchor = dates.start;
          _end = dates.end;
        });
      }
      return;
    }
    final date = await showDatePicker(
      context: context,
      locale: calendarLocale,
      firstDate: first,
      lastDate: last,
      initialDate:
          (deadline ? _deadline : _anchor) ??
          DateTime(now.year, now.month, now.day),
    );
    if (mounted && date != null) {
      setState(() {
        if (deadline) {
          _deadline = date;
        } else {
          _anchor = date;
        }
      });
    }
  }

  Future<void> _review(SchemePeriod period, bool selected) async {
    final s = editorStrings(context);
    final use = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.p7aPeriodDetails),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatSchemePeriod(period, s),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (selected) Text(s.p7aCurrentPeriod),
              const SizedBox(height: 10),
              if (widget.bundle.showDeadline)
                Text(
                  period.deadline == null
                      ? s.p7MissingDeadline
                      : '${s.p7Deadline} · ${formatSchemeDate(period.deadline!, s)}',
                ),
              Text('${s.editorVersion} ${period.templateVersion}'),
              Text('${s.p7RuleRevision} ${period.ruleVersion}'),
            ],
          ),
        ),
        actions: [
          TactileButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          if (!selected)
            TactileButton(
              onPressed: () => Navigator.pop(context, true),
              variant: TactileButtonVariant.primary,
              child: Text(s.p7aUsePeriod),
            ),
        ],
      ),
    );
    if (use == true && mounted) await _select(period);
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final title = widget.bundle.label('period', s.p7Period, s.localeName);
    final labels = {
      PeriodKind.custom: s.p7CustomPeriod,
      PeriodKind.fixed: s.p7aFixed,
      PeriodKind.rolling: s.p7aRolling,
    };
    final preview = _anchor == null
        ? null
        : SchemePeriod.create(
            widget.bundle,
            id: 'draft',
            kind: _kind,
            anchor: schemeDay(_anchor!),
            end: _end == null
                ? null
                : schemeDay(
                    DateTime.utc(_end!.year, _end!.month, _end!.day + 1),
                  ),
            deadline: _deadline == null ? null : schemeDay(_deadline!),
          );
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          BrandedPageHeader(title: title, icon: Icons.date_range_outlined),
          Expanded(
            child: FutureBuilder(
              future: _periods,
              builder: (_, snapshot) => BoundedList(
                children: [
                  if (snapshot.hasError) Text(s.editorSaveError),
                  if (!snapshot.hasData && !snapshot.hasError)
                    const Center(child: CircularProgressIndicator()),
                  if (snapshot.hasData &&
                      snapshot.requireData.periods.isNotEmpty)
                    FormSectionTile(
                      label: s.p7aSavedPeriods,
                      icon: Icons.history,
                      child: Column(
                        children: [
                          for (final period in snapshot.requireData.periods)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(formatSchemePeriod(period, s)),
                              subtitle:
                                  period.id == snapshot.requireData.selected
                                  ? Text(s.p7aCurrentPeriod)
                                  : null,
                              leading: Icon(
                                period.id == snapshot.requireData.selected
                                    ? Icons.check_circle_outline
                                    : Icons.history,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              selected:
                                  period.id == snapshot.requireData.selected,
                              onTap: _busy
                                  ? null
                                  : () => _review(
                                      period,
                                      period.id ==
                                          snapshot.requireData.selected,
                                    ),
                            ),
                        ],
                      ),
                    ),
                  if (snapshot.hasData) ...[
                    const SizedBox(height: 12),
                    if (!_creating)
                      TactileButton.icon(
                        onPressed: () => setState(() => _creating = true),
                        icon: const Icon(Icons.add),
                        label: Text(s.p7aNewPeriod),
                        variant: TactileButtonVariant.primary,
                      )
                    else
                      FormSectionTile(
                        label: s.p7aNewPeriod,
                        icon: Icons.event_available_outlined,
                        supportingText: widget.bundle.label(
                          'periodHint',
                          s.p7PeriodHint,
                          s.localeName,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 10),
                            DropdownButtonFormField<PeriodKind>(
                              initialValue: _kind,
                              isExpanded: true,
                              isDense: false,
                              itemHeight: null,
                              items: [
                                for (final kind in widget.bundle.periods)
                                  DropdownMenuItem(
                                    value: kind,
                                    child: Text(labels[kind]!, maxLines: 3),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (kind) => setState(() {
                                      _kind = kind!;
                                      _anchor = null;
                                      _end = null;
                                    }),
                            ),
                            const SizedBox(height: 10),
                            TactileButton.icon(
                              onPressed: _busy ? null : () => _chooseDate(),
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text(
                                preview == null
                                    ? s.selectDate
                                    : formatSchemePeriod(preview, s),
                              ),
                            ),
                            if (widget.bundle.showDeadline) ...[
                              const SizedBox(height: 8),
                              TactileButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _chooseDate(deadline: true),
                                icon: const Icon(Icons.flag_outlined),
                                label: Text(
                                  _deadline == null
                                      ? s.p7ChooseDeadline
                                      : '${s.p7Deadline} · ${formatSchemeDate(schemeDay(_deadline!), s)}',
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            TactileButton(
                              variant: TactileButtonVariant.primary,
                              loading: _busy,
                              onPressed: _busy || preview == null
                                  ? null
                                  : () => _select(
                                      SchemePeriod(
                                        id: const Uuid().v4(),
                                        kind: preview.kind,
                                        templateId: preview.templateId,
                                        templateVersion:
                                            preview.templateVersion,
                                        ruleVersion: preview.ruleVersion,
                                        start: preview.start,
                                        end: preview.end,
                                        deadline: preview.deadline,
                                      ),
                                    ),
                              child: Text(s.save),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openSchemeReport(
  BuildContext context,
  ProfessionCreationStore store,
  RecordingCollection profession,
  List<LayoutRevision> history,
  List<RecordingRecord> records,
  int version, {
  ManagedAttachmentFiles? originals,
}) async {
  try {
    final active = history.singleWhere(
      (revision) => revision.version == version,
    );
    var current = phase7Bundles[(active.templateId, active.templateVersion)];
    final historical = store.trialsEnabled && records.isNotEmpty;
    if (historical) {
      await store.requireHistoricalReport(active);
      current = await const HistoricalCpdBundles().readOnlyRecipeVersion(
        store.repository,
        active.templateId!,
        active.templateVersion!,
      );
    } else {
      await store.requireOwnedReport(active);
    }
    final periods = SchemePeriodStore(store.repository);
    var selection = await periods.load(profession.id);
    if (selection.selected == null && !historical && current != null) {
      if (!context.mounted) return;
      await pickSchemePeriod(context, store, profession, current);
      selection = await periods.load(profession.id);
    }
    if (!context.mounted) return;
    final period =
        selection.periods
            .where((item) => item.id == selection.selected)
            .firstOrNull ??
        (historical && current != null
            ? _recordDatePeriod(current, records, history)
            : null);
    if (period == null) {
      if (historical) throw StateError('No verified historical report period.');
      return;
    }
    final retained = await const HistoricalCpdBundles().read(
      store.repository,
      period.templateId,
      period.templateVersion,
      period.ruleVersion,
    );
    final installed =
        phase7Bundles[(period.templateId, period.templateVersion)];
    final bundle =
        retained ??
        (!historical && installed?.ruleVersion == period.ruleVersion
            ? installed
            : null);
    if (bundle == null) {
      throw StateError('The pinned historical rules are unavailable.');
    }
    final baseline = history.firstWhere(
      (layout) =>
          layout.templateId == bundle.recipe.id &&
          layout.templateVersion == period.templateVersion,
    );
    if (historical) {
      await store.requireHistoricalReport(baseline);
    } else {
      await store.requireOwnedReport(baseline);
    }
    final reportSelection = await store.reportAt(profession.id, version);
    final result = await loadSchemeProgress(
      repository: store.repository,
      bundle: bundle,
      period: period,
      history: history,
      records: records,
      originals: originals,
    );
    if (!context.mounted) return;
    final s = editorStrings(context);
    final request = await pickPresentation(context, store);
    if (request == null || !context.mounted) return;
    final outputFonts = await _schemeFonts();
    final icon = bundle.branding == ReportBranding.standard
        ? (await rootBundle.load(
            'assets/icon/1024x1024_app_icon.png',
          )).buffer.asUint8List()
        : null;
    if (!context.mounted) return;
    final layoutStatus = SchemeReportRules(
      version: bundle.ruleVersion,
      requiredDefinitions: bundle.protectedKeys.map(
        (key) => bundle.field(key).definition.id,
      ),
    ).assess(baseline, LayoutDraft(active), reportSelection);
    final excluded = reportSelection.excluded;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(s.p6OpenReport),
            actions: [
              IconButton(
                tooltip: s.p7aPeriodDetails,
                icon: const Icon(Icons.info_outline),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(s.p7aPeriodDetails),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatSchemePeriod(period, s)),
                        for (final line in schemeTraceabilityDetails(
                          bundle,
                          period,
                          s,
                        ))
                          Text(line),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(s.cancel),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: PdfPreview(
            initialPageFormat: PdfPageFormat.a4,
            allowSharing: store.trialsEnabled,
            allowPrinting: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            useActions: store.trialsEnabled,
            onError: rehearsalReportError,
            build: (_) => buildSchemeReport(
              bundle: bundle,
              progress: result.progress,
              bindings: result.bindings,
              evidence: result.evidence,
              strings: s,
              practitioner: request.practitioner,
              reportLocale: request.locale,
              brandIcon: icon,
              excluded: excluded,
              regular: outputFonts.regular,
              bold: outputFonts.bold,
              incompleteLayout: layoutStatus.incomplete,
            ),
          ),
        ),
      ),
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editorStrings(context).editorSaveError)),
      );
    }
  }
}

SchemePeriod? _recordDatePeriod(
  ProfessionTemplateBundle bundle,
  List<RecordingRecord> records,
  List<LayoutRevision> history,
) {
  final days = <String>[];
  for (final record in records.where((record) => !record.deleted)) {
    final fields = cpdFieldBindings(
      resolveFields(record.layoutVersion, history),
    );
    if (record.values[fields['cpd.activityDate']] case final String day
        when isCalendarDay(day)) {
      days.add(day);
    }
  }
  if (days.isEmpty) return null;
  days.sort();
  return SchemePeriod(
    id: 'historical-record-dates',
    kind: PeriodKind.custom,
    templateId: bundle.recipe.id,
    templateVersion: bundle.recipe.version,
    ruleVersion: bundle.ruleVersion,
    start: days.first,
    end: schemeDay(
      DateTime.parse('${days.last}T00:00:00Z').add(const Duration(days: 1)),
    ),
  );
}

Future<({ReportLocale locale, String practitioner})?> pickPresentation(
  BuildContext context,
  ProfessionCreationStore store,
) async {
  final strings = editorStrings(context);
  final current = ReportLanguage.fromStored(
    (await store.settings())['reportLocale'],
  );
  if (!context.mounted) return null;
  final request =
      await showDialog<({ReportLanguage language, String practitioner})>(
        context: context,
        builder: (_) => _ReportPreferences(initial: current),
      );
  if (request == null) return null;
  if (current != request.language) {
    await store.saveSetting('reportLocale', request.language.tag);
  }
  return (
    locale: await ReportLocale.resolve(request.language, strings),
    practitioner: request.practitioner,
  );
}

class _ReportPreferences extends StatefulWidget {
  const _ReportPreferences({required this.initial});
  final ReportLanguage initial;

  @override
  State<_ReportPreferences> createState() => _ReportPreferencesState();
}

class _ReportPreferencesState extends State<_ReportPreferences> {
  final _name = TextEditingController();
  late ReportLanguage _language = widget.initial;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return AlertDialog(
      title: Text(s.p6OpenReport),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: InputDecoration(labelText: s.p7Practitioner),
            ),
            ReportLanguageTile(
              language: _language,
              onChanged: (value) => setState(() => _language = value),
            ),
          ],
        ),
      ),
      actions: [
        TactileButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        TactileButton(
          onPressed: () => Navigator.pop(context, (
            language: _language,
            practitioner: _name.text,
          )),
          variant: TactileButtonVariant.primary,
          child: Text(s.continueLabel),
        ),
      ],
    );
  }
}

Future<void> openLayoutReport(
  BuildContext context,
  ProfessionCreationStore store,
  RecordingCollection profession,
  List<LayoutRevision> history,
  List<RecordingRecord> records,
  Set<String> exclusions,
) async {
  final request = await pickPresentation(context, store);
  if (request == null || !context.mounted) return;
  final app = editorStrings(context);
  final locale = request.locale;
  final s = locale.strings;
  final outputFonts = await _schemeFonts();
  if (!context.mounted) return;

  String valueLabel(LayoutField field, Object value) {
    final definition = field.definition;
    return switch (definition.kind) {
      FieldKind.date => locale.date(DateTime.parse(value as String)),
      FieldKind.duration => locale.duration(value as int),
      FieldKind.integer => locale.integer(value as int),
      FieldKind.decimal => locale.decimal(value as String),
      FieldKind.attachments => (value as List).join(', '),
      FieldKind.multipleChoices =>
        (definition.displayValue(value) as List).join(', '),
      _ => definition.displayValue(value).toString(),
    };
  }

  final activities = [
    for (final record in records.where((record) => !record.deleted))
      (
        title:
            resolveFields(record.layoutVersion, history)
                .where((field) => field.definition.id == 'cpd.title')
                .where((field) => !exclusions.contains(field.id))
                .map((field) => record.values[field.id] as String?)
                .firstOrNull ??
            s.noTitle,
        status: '',
        fields: [
          for (final field in resolveFields(record.layoutVersion, history))
            if (!exclusions.contains(field.id) &&
                field.definition.id != 'cpd.title')
              if (record.values[field.id] case final value?)
                (
                  label: field.localizedLabel(locale.tag),
                  value: valueLabel(field, value),
                ),
        ],
      ),
  ];
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(app.editorExport)),
        body: PdfPreview(
          initialPageFormat: PdfPageFormat.a4,
          allowSharing: false,
          allowPrinting: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          useActions: false,
          onError: rehearsalReportError,
          build: (_) => buildActivityDocument(
            ActivityDocumentData(
              title: s.cpdPdfDocumentTitle,
              appName: 'CPD Progress Tracker',
              attribution: s.p7aAttribution,
              documentTag: s.p7Internal,
              summaryTitle: s.cpdRecordsTitle,
              metadata: [
                profession.label,
                if (request.practitioner.trim().isNotEmpty)
                  request.practitioner.trim(),
              ],
              summary: const [],
              activities: activities,
              evidenceTitle: s.p7EvidenceIndex,
              evidence: const [],
              continued: s.cpdPdfContinuedTitle,
              pageOf: s.pageOf,
            ),
            regular: outputFonts.regular,
            bold: outputFonts.bold,
          ),
        ),
      ),
    ),
  );
}
