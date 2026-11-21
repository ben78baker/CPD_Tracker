import 'dart:typed_data';

import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
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
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/widgets/profession_card.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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

Future<Uint8List> exampleSchemeReport(BuildContext context) async {
  final strings = editorStrings(context);
  final fallback = await _schemeFonts(strings.localeName);
  return buildBundleExampleReport(
    bundle: nursingBundle,
    period: rehearsalPeriod,
    strings: strings,
    fallback: fallback,
  );
}

Future<List<pw.Font>> _schemeFonts(String locale) async => [
  if (locale == 'hi')
    await PdfGoogleFonts.notoSansDevanagariRegular().timeout(
      const Duration(seconds: 12),
    ),
];

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
        targetMenuLabel: bundle == null ? null : s.p7ConfigurePeriod,
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
    ),
  ),
);

class _PeriodsPage extends StatefulWidget {
  const _PeriodsPage({
    required this.store,
    required this.collection,
    required this.bundle,
  });
  final SchemePeriodStore store;
  final String collection;
  final ProfessionTemplateBundle bundle;

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

  Future<void> _select(SchemePeriod period) async {
    setState(() => _busy = true);
    try {
      await widget.store.select(widget.collection, period);
      if (mounted) Navigator.pop(context);
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
    final first = DateTime(1900);
    final last = DateTime(now.year + 30, 12, 31);
    if (!deadline && _kind == PeriodKind.custom) {
      final dates = await showDateRangePicker(
        context: context,
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

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final labels = {
      PeriodKind.custom: s.p7CustomPeriod,
      PeriodKind.fixed: s.p7FixedPeriod,
      PeriodKind.rolling: s.p7RollingPeriod,
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
      appBar: AppBar(title: Text(s.p7Period)),
      body: FutureBuilder(
        future: _periods,
        builder: (_, snapshot) => BoundedList(
          children: [
            Text(
              widget.bundle.label('periodHint', s.p7PeriodHint, s.localeName),
            ),
            if (snapshot.hasError) Text(s.editorSaveError),
            for (final period
                in snapshot.data?.periods ?? const <SchemePeriod>[])
              ListTile(
                title: Text(formatSchemePeriod(period, s)),
                subtitle: Text(
                  'v${period.templateVersion} · v${period.ruleVersion}',
                ),
                leading: Icon(
                  period.id == snapshot.data?.selected
                      ? Icons.check_circle_outline
                      : Icons.history,
                ),
                onTap: _busy ? null : () => _select(period),
              ),
            DropdownButton<PeriodKind>(
              isExpanded: true,
              value: _kind,
              items: [
                for (final kind in widget.bundle.periods)
                  DropdownMenuItem(value: kind, child: Text(labels[kind]!)),
              ],
              onChanged: _busy
                  ? null
                  : (kind) => setState(() {
                      _kind = kind!;
                      _anchor = null;
                      _end = null;
                    }),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _chooseDate(),
              child: Text(
                preview == null ? s.selectDate : formatSchemePeriod(preview, s),
              ),
            ),
            if (widget.bundle.showDeadline)
              OutlinedButton(
                onPressed: _busy ? null : () => _chooseDate(deadline: true),
                child: Text(
                  _deadline == null
                      ? s.p7ChooseDeadline
                      : '${s.p7Deadline} · ${formatSchemeDate(schemeDay(_deadline!), s)}',
                ),
              ),
            FilledButton(
              onPressed: _busy || preview == null
                  ? null
                  : () => _select(
                      SchemePeriod(
                        id: const Uuid().v4(),
                        kind: preview.kind,
                        templateId: preview.templateId,
                        templateVersion: preview.templateVersion,
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
    final current = phase7Bundles[(active.templateId, active.templateVersion)]!;
    await store.requireOwnedReport(active);
    final periods = SchemePeriodStore(store.repository);
    var selection = await periods.load(profession.id);
    if (selection.selected == null) {
      if (!context.mounted) return;
      await pickSchemePeriod(context, store, profession, current);
      selection = await periods.load(profession.id);
    }
    if (selection.selected == null || !context.mounted) return;
    final period = selection.periods.singleWhere(
      (item) => item.id == selection.selected,
    );
    final bundle = phase7Bundles[(period.templateId, period.templateVersion)]!;
    final baseline = history.firstWhere(
      (layout) =>
          layout.templateId == bundle.recipe.id &&
          layout.templateVersion == period.templateVersion,
    );
    await store.requireOwnedReport(baseline);
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
    final practitioner = await showDialog<String>(
      context: context,
      builder: (_) => const _PractitionerDialog(),
    );
    if (practitioner == null || !context.mounted) return;
    final fallback = await _schemeFonts(s.localeName);
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
          appBar: AppBar(title: Text(s.p6OpenReport)),
          body: PdfPreview(
            initialPageFormat: PdfPageFormat.a4,
            allowSharing: false,
            allowPrinting: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            useActions: false,
            build: (_) => buildSchemeReport(
              bundle: bundle,
              progress: result.progress,
              bindings: result.bindings,
              evidence: result.evidence,
              strings: s,
              practitioner: practitioner,
              excluded: excluded,
              fallback: fallback,
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

class _PractitionerDialog extends StatefulWidget {
  const _PractitionerDialog();

  @override
  State<_PractitionerDialog> createState() => _PractitionerDialogState();
}

class _PractitionerDialogState extends State<_PractitionerDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return AlertDialog(
      title: Text(s.p7Practitioner),
      content: TextField(controller: _name, maxLength: 120),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text(s.continueLabel),
        ),
      ],
    );
  }
}
