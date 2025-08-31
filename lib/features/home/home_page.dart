import 'package:flutter/material.dart';

enum Period { week, month, ytd, year }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Period _period = Period.week;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CPD Tracker'),
        actions: [
          IconButton(
            tooltip: 'Add Profession',
            onPressed: _onAddProfession,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Greeting / header
            Text(
              'Welcome',
              style: text.headlineMedium,
            ),
            const SizedBox(height: 12),

            // Period filter row
            Row(
              children: [
                Text('Show hours for:', style: text.titleMedium),
                const SizedBox(width: 12),
                _PeriodChip(
                  label: 'Week',
                  selected: _period == Period.week,
                  onTap: () => setState(() => _period = Period.week),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Month',
                  selected: _period == Period.month,
                  onTap: () => setState(() => _period = Period.month),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'YTD',
                  selected: _period == Period.ytd,
                  onTap: () => setState(() => _period = Period.ytd),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Year',
                  selected: _period == Period.year,
                  onTap: () => setState(() => _period = Period.year),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Profession tiles header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Your Professions', style: text.titleLarge),
                TextButton.icon(
                  onPressed: _onAddProfession,
                  icon: const Icon(Icons.add),
                  label: const Text('Add New'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Profession grid (placeholder data for now)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 700;
                final crossAxisCount = isWide ? 2 : 1;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  childAspectRatio: isWide ? 2.8 : 1.8,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _ProfessionTile(
                      title: 'Electrician',
                      hoursForPeriod: _hoursLabel(0.0),
                      period: _period,
                      targetProgress: 0.28, // placeholder 28%
                      onNewEntry: _onNewEntry,
                      onScanQr: _onScanQR,
                      onViewRecords: _onViewRecords,
                      onMenuSelected: _onProfMenuSelected,
                    ),
                    // Add more tiles once DB is wired up
                  ],
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onNewEntry,
        icon: const Icon(Icons.add),
        label: const Text('New CPD Record'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      backgroundColor: cs.surface,
    );
  }

  String _hoursLabel(double hours) {
    // This will later reflect a DB query filtered by _period.
    // For now we format a placeholder.
    return '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)} h';
  }

  // ===== Placeholder handlers (wire to real pages later) =====

  void _onAddProfession() {
    _toast('Add Profession (placeholder)');
  }

  void _onNewEntry() {
    _toast('New Entry (placeholder)');
  }

  void _onScanQR() {
    _toast('Scan QR (placeholder)');
  }

  void _onViewRecords() {
    _toast('View Records (placeholder)');
  }

  void _onProfMenuSelected(_ProfMenu action) {
    switch (action) {
      case _ProfMenu.editTitle:
        _toast('Edit profession title (placeholder)');
        break;
      case _ProfMenu.addTarget:
        _toast('Add periodic target (placeholder)');
        break;
      case _ProfMenu.showDeleted:
        _toast('Show deleted records (placeholder)');
        break;
      case _ProfMenu.shareExport:
        _toast('Share / export / print (placeholder)');
        break;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withAlpha((255 * 0.12).round())
              : cs.surface,
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

enum _ProfMenu { editTitle, addTarget, showDeleted, shareExport }

class _ProfessionTile extends StatelessWidget {
  const _ProfessionTile({
    required this.title,
    required this.hoursForPeriod,
    required this.period,
    required this.targetProgress,
    required this.onNewEntry,
    required this.onScanQr,
    required this.onViewRecords,
    required this.onMenuSelected,
  });

  final String title;
  final String hoursForPeriod;
  final Period period;
  final double targetProgress;
  final VoidCallback onNewEntry;
  final VoidCallback onScanQr;
  final VoidCallback onViewRecords;
  final void Function(_ProfMenu) onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    String periodLabel() {
      switch (period) {
        case Period.week:
          return 'This week';
        case Period.month:
          return 'This month';
        case Period.ytd:
          return 'Year to date';
        case Period.year:
          return 'This year';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header row: title + menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(title, style: text.titleLarge),
                ),
                PopupMenuButton<_ProfMenu>(
                  tooltip: 'Options',
                  onSelected: onMenuSelected,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ProfMenu.editTitle,
                      child: Text('Edit profession title'),
                    ),
                    PopupMenuItem(
                      value: _ProfMenu.addTarget,
                      child: Text('Add periodic target'),
                    ),
                    PopupMenuItem(
                      value: _ProfMenu.showDeleted,
                      child: Text('Show deleted records'),
                    ),
                    PopupMenuItem(
                      value: _ProfMenu.shareExport,
                      child: Text('Share / export / print'),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Hours summary
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$hoursForPeriod of CPD • ${periodLabel()}',
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 12),

            // Target progress (example)
            _ProgressBar(
              progress: targetProgress,
              label: '${(targetProgress * 100).toStringAsFixed(0)}% towards target',
            ),

            const Spacer(),

            // Actions row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onNewEntry,
                    icon: const Icon(Icons.add),
                    label: const Text('New Entry'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onScanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onViewRecords,
                    child: const Text('View Records'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.label,
  });

  final double progress; // 0..1
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0), // <-- fix here
            minHeight: 10,
            backgroundColor: cs.surface,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}