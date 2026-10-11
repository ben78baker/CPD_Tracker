import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings_store.dart';
import '../theme/app_theme.dart';
import 'branded_headers.dart';
import 'tactile_button.dart';

class ProfessionCard extends StatelessWidget {
  const ProfessionCard({
    super.key,
    required this.name,
    required this.onAdd,
    required this.onScan,
    required this.onView,
    required this.onSearch,
    required this.onRename,
    required this.onDelete,
    required this.target,
    required this.computeCompleted,
    required this.onSetTarget,
    required this.refreshToken,
  });

  final int refreshToken;
  final String name;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final VoidCallback onView;
  final VoidCallback onSearch;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final (int minutes, String cycle)? target;
  final Future<int> Function(String cycle) computeCompleted;
  final VoidCallback onSetTarget;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final brand = context.brandColors;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandedSectionHeader(
            title: name,
            icon: Icons.work_outline_rounded,
            prominent: true,
            trailing: PopupMenuButton<String>(
              color: AppColors.surface,
              icon: Icon(Icons.more_vert, color: brand.accentDark),
              onSelected: (value) {
                if (value == 'set_target') onSetTarget();
                if (value == 'search_records') onSearch();
                if (value == 'rename') onRename();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'set_target',
                  child: Text(AppLocalizations.of(ctx)!.setEditTarget),
                ),
                const PopupMenuItem(
                  value: 'search_records',
                  child: Text('Search Records'),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Text(AppLocalizations.of(ctx)!.renameProfession),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(AppLocalizations.of(ctx)!.deleteProfession),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackActions = tactileButtonsNeedStacking(
                      context,
                      constraints.maxWidth,
                      [loc.addEntry, loc.scanQr],
                    );

                    final addButton = TactileButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: Text(loc.addEntry),
                      variant: TactileButtonVariant.primary,
                    );
                    final scanButton = TactileButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(loc.scanQr),
                    );

                    if (stackActions) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          addButton,
                          const SizedBox(height: 8),
                          scanButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: addButton),
                        const SizedBox(width: 8),
                        Expanded(child: scanButton),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TactileButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.list),
                    label: Text(loc.viewRecords),
                  ),
                ),
                const SizedBox(height: 12),
                _TargetProgress(
                  key: ValueKey('$name-$refreshToken'),
                  target: target,
                  computeCompleted: computeCompleted,
                  onSetTarget: onSetTarget,
                  refreshToken: refreshToken,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetProgress extends StatefulWidget {
  const _TargetProgress({
    super.key,
    required this.target,
    required this.computeCompleted,
    required this.onSetTarget,
    required this.refreshToken,
  });

  final (int minutes, String cycle)? target;
  final Future<int> Function(String cycle) computeCompleted;
  final VoidCallback onSetTarget;
  final int refreshToken;

  @override
  State<_TargetProgress> createState() => _TargetProgressState();
}

class _TargetProgressState extends State<_TargetProgress> {
  (int minutes, String cycle)? _target;
  int _completed = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _TargetProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target ||
        oldWidget.refreshToken != widget.refreshToken) {
      _target = widget.target;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final target = _target;
    if (target == null) return;
    setState(() => _loading = true);
    final minutes = await widget.computeCompleted(target.$2);
    if (!mounted) return;
    setState(() {
      _completed = minutes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 10),
      );
    }
    if (target == null) {
      return TactileButton.icon(
        onPressed: widget.onSetTarget,
        icon: const Icon(Icons.flag_outlined),
        label: Text(AppLocalizations.of(context)!.setEditTarget),
      );
    }

    final total = target.$1;
    final cycle = target.$2;
    final ratio = total <= 0 ? 0.0 : (_completed / total).clamp(0.0, 1.0);
    final remaining = (total - _completed).clamp(0, total);
    final remainingHours = remaining ~/ 60;
    final remainingMinutes = remaining % 60;
    final loc = AppLocalizations.of(context)!;
    final cycleLabel = switch (cycle) {
      'week' => loc.thisWeek,
      'month' => loc.thisMonth,
      _ => loc.thisYear,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          remaining == 0
              ? loc.targetAchieved(cycleLabel)
              : loc.timeRemaining(remainingHours, remainingMinutes, cycleLabel),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(minHeight: 10, value: ratio),
        ),
        FutureBuilder<String>(
          future: SettingsStore.instance.getWeekStart(),
          builder: (context, snapshot) {
            final value = snapshot.data ?? 'locale';
            final String? label = switch (value) {
              'monday' => loc.weekStartsOnDay(loc.monday),
              'sunday' => loc.weekStartsOnDay(loc.sunday),
              'saturday' => loc.weekStartsOnDay(loc.saturday),
              _ => null,
            };
            if (label == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
