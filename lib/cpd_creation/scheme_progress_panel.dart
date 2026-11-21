import 'package:flutter/material.dart';

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
  });

  final ProfessionTemplateBundle bundle;
  final SchemeProgress? progress;
  final VoidCallback onPeriods;

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
        if (bundle.showDeadline ||
            result.incomplete > 0 ||
            result.activities.isEmpty) ...[
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
              if (result.incomplete > 0)
                Text(
                  '${s.p7ReviewLog} · ${result.incomplete}',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                )
              else if (result.activities.isEmpty)
                Text(s.noRecordsInSelectedPeriod, style: text.bodySmall),
            ],
          ),
        ],
      ],
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
