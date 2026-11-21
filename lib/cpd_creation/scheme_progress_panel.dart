import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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
    final result = progress;
    if (result == null) {
      return TactileButton.icon(
        onPressed: onPeriods,
        icon: const Icon(Icons.date_range_outlined),
        label: Text(s.p7ConfigurePeriod),
      );
    }
    final small = Theme.of(context).textTheme.bodySmall;
    final title = Theme.of(context).textTheme.labelLarge;
    final warning = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in bundle.tileMetrics)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GoalProgress(
              name: bundle.label(id, id, s.localeName),
              metric: bundle.metrics.singleWhere((metric) => metric.id == id),
              progress: result.metrics[id]!,
            ),
          ),
        TextButton(
          onPressed: onPeriods,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(vertical: 4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.p7Period, style: title),
              Text(formatSchemePeriod(result.period, s), style: small),
              if (bundle.showDeadline)
                Text(
                  result.period.deadline == null
                      ? s.p7MissingDeadline
                      : '${s.p7Deadline} · ${formatSchemeDate(result.period.deadline!, s)}',
                  style: small,
                ),
            ],
          ),
        ),
        if (result.incomplete > 0 || result.activities.isEmpty)
          Text(
            result.activities.isEmpty
                ? s.noRecordsInSelectedPeriod
                : '${s.p7ReviewLog} · ${result.incomplete}',
            style: small?.copyWith(color: warning),
          ),
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
    final summary =
        '${formatSchemeMinutes(progress.eligible, s)} / '
        '${formatSchemeMinutes(metric.target, s)}';
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.textTheme.labelLarge),
        Text('${s.p7Eligible} · $summary', style: theme.textTheme.bodySmall),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: (progress.eligible / metric.target).clamp(0, 1).toDouble(),
            semanticsLabel: name,
          ),
        ),
      ],
    );
  }
}
