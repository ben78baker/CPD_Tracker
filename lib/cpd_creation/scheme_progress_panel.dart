import 'package:flutter/material.dart';

import '../cpd_compatibility/cpd_layout_policy.dart';
import '../l10n/app_localizations.dart';
import '../widgets/profession_card.dart';
import '../widgets/tactile_button.dart';
import 'scheme_progress.dart';
import 'scheme_report.dart';
import 'template_bundle.dart';

class SchemeProgressPanel extends StatelessWidget {
  const SchemeProgressPanel({
    super.key,
    required this.bundle,
    required this.progress,
    required this.onPeriods,
    required this.onOpenRecord,
  });

  final ProfessionTemplateBundle bundle;
  final SchemeProgress? progress;
  final VoidCallback onPeriods;
  final ValueChanged<String> onOpenRecord;

  Future<void> _review(
    BuildContext context,
    List<ActivityResult> activities,
  ) async {
    final recordId = await showDialog<String>(
      context: context,
      builder: (context) {
        final s = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(s.p7ReviewLog),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.46,
              ),
              child: ListView.builder(
                primary: false,
                shrinkWrap: true,
                itemCount: activities.length,
                itemBuilder: (context, index) {
                  final entry = activities[index];
                  final titleId = cpdFieldBindings(
                    entry.activity.fields,
                  )['cpd.title'];
                  final title = entry.activity.values[titleId];
                  return ListTile(
                    title: Text(
                      title is String && title.trim().isNotEmpty
                          ? title
                          : s.noTitle,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.day case final day?)
                          Text(formatSchemeDate(day, s)),
                        for (final issue in entry.issues)
                          Text(schemeIssueLabel(issue, s)),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(entry.activity.id),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        );
      },
    );
    if (context.mounted && recordId != null) onOpenRecord(recordId);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final periodLabel = bundle.label('period', s.p7Period, s.localeName);
    final result = progress;
    if (result == null) {
      return TactileButton.icon(
        onPressed: onPeriods,
        icon: const Icon(Icons.date_range_outlined),
        label: Text(periodLabel),
      );
    }
    final flagged = result.activities
        .where((entry) => entry.issues.isNotEmpty)
        .toList();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.p7Eligible, style: text.bodySmall),
        for (final id in bundle.tileMetrics) ...[
          const SizedBox(height: 6),
          _GoalProgress(
            name: bundle.label(id, id, s.localeName),
            metric: bundle.metrics.singleWhere((metric) => metric.id == id),
            progress: result.metrics[id]!,
          ),
        ],
        const SizedBox(height: 8),
        TactileButton.icon(
          onPressed: onPeriods,
          icon: const Icon(Icons.date_range_outlined),
          label: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(periodLabel),
              Text(formatSchemePeriod(result.period, s), style: text.bodySmall),
            ],
          ),
        ),
        if (bundle.showDeadline || result.activities.isEmpty) ...[
          const SizedBox(height: 7),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (bundle.showDeadline)
                Text(
                  result.period.deadline == null
                      ? s.p7MissingDeadline
                      : '${s.p7Deadline} · ${formatSchemeDate(result.period.deadline!, s)}',
                  style: text.bodySmall,
                ),
              if (result.activities.isEmpty)
                Text(s.noRecordsInSelectedPeriod, style: text.bodySmall),
            ],
          ),
        ],
        if (flagged.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TactileButton.icon(
              minimumSize: const Size(64, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              icon: const Icon(Icons.fact_check_outlined, size: 19),
              label: Text('${s.p7ReviewLog} · ${flagged.length}'),
              onPressed: () => _review(context, flagged),
            ),
          ),
        ],
      ],
    );
  }
}

class SchemeRecordAdvisory extends StatelessWidget {
  const SchemeRecordAdvisory({super.key, required this.issues});

  final Set<ActivityIssue> issues;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: error, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final issue in issues)
                    Text(
                      schemeIssueLabel(issue, s),
                      style: theme.textTheme.bodyMedium?.copyWith(color: error),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({
    required this.name,
    required this.metric,
    required this.progress,
  });
  final String name;
  final SchemeMetric metric;
  final MetricProgress progress;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final time =
        '${formatSchemeMinutes(progress.eligible, s)} / '
        '${formatSchemeMinutes(metric.target, s)}';
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 10,
          children: [
            Text(name, style: text.labelLarge),
            Text(time, style: text.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        CpdTargetBar(
          value: (progress.eligible / metric.target).clamp(0, 1).toDouble(),
          label: name,
        ),
      ],
    );
  }
}
