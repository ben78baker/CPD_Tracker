import 'package:flutter/material.dart';
import 'entry_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'add_entry_page.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

class CpdRecordsPage extends StatefulWidget {
  const CpdRecordsPage({super.key, required this.profession});
  final String profession;

  @override
  State<CpdRecordsPage> createState() => _CpdRecordsPageState();
}

class _CpdRecordsPageState extends State<CpdRecordsPage> {
  final _repo = EntryRepository();
  final _settings = SettingsStore.instance;
  List<CpdEntry> _entries = [];
  String _fmt = 'dd/MM/yyyy';
  DateTimeRange? _selectedRange;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.loadForProfession(widget.profession);
    list.sort((a, b) => b.date.compareTo(a.date)); // newest first
    final fmt = await _settings.getDateFormat();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _fmt = fmt;
    });
  }

  Future<void> _edit(CpdEntry e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEntryPage(profession: e.profession, existingEntry: e),
      ),
    );
    _load();
  }

  Future<void> _toggleDelete(CpdEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.deleted ? 'Restore record?' : 'Delete record?'),
        content: Text(e.deleted
            ? 'Do you want to restore this record?'
            : 'Do you want to delete this record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(e.deleted ? 'Restore' : 'Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.setDeleted(e.id, !e.deleted);
      _load();
    }
  }

  void _showAttachments(CpdEntry e) {
    if (e.attachments.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => const AlertDialog(
          title: Text('Attachments'),
          content: Text('No items have been added.'),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attachments'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: e.attachments.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(e.attachments[i]),
            ),
          ),
        ),
      ),
    );
  }

  // Return unique entry dates (normalized to Y/M/D) sorted ascending
  List<DateTime> _distinctSortedEntryDates() {
    final set = <DateTime>{};
    for (final e in _entries) {
      set.add(DateTime(e.date.year, e.date.month, e.date.day));
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<DateTimeRange?> _pickRangeSimple(BuildContext context) async {
    if (_entries.isEmpty) return null;

    // Compute generous bounds similar to add_entry_page (±10 years from now) but
    // also include dataset min/max if they extend beyond.
    DateTime minD = DateTime(9999);
    DateTime maxD = DateTime(0);
    for (final e in _entries) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      if (d.isBefore(minD)) minD = d;
      if (d.isAfter(maxD)) maxD = d;
    }
    final now = DateTime.now();
    final defaultFirst = DateTime(now.year - 10, 1, 1);
    final defaultLast  = DateTime(now.year + 10, 12, 31);
    final firstDate = (minD.isBefore(defaultFirst)) ? DateTime(minD.year, 1, 1) : defaultFirst;
    final lastDate  = (maxD.isAfter(defaultLast))  ? DateTime(maxD.year, 12, 31) : defaultLast;

    DateTime from = _selectedRange?.start ?? minD;
    DateTime to   = _selectedRange?.end   ?? maxD;

    String fmt(DateTime d) => formatDate(d, _fmt);

    return await showModalBottomSheet<DateTimeRange>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16, right: 16, top: 12,
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              bool valid = !from.isAfter(to);

              Future<void> pickFrom() async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: from.isBefore(firstDate) ? firstDate : (from.isAfter(lastDate) ? lastDate : from),
                  firstDate: firstDate,
                  lastDate: lastDate,
                );
                if (picked != null) setState(() => from = picked);
              }

              Future<void> pickTo() async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: to.isBefore(firstDate) ? firstDate : (to.isAfter(lastDate) ? lastDate : to),
                  firstDate: firstDate,
                  lastDate: lastDate,
                );
                if (picked != null) setState(() => to = picked);
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, DateTimeRange(start: minD, end: maxD)),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share all records'),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: Theme.of(ctx).dividerColor.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text('Select period', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 12),

                  Text('From', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: pickFrom,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(fmt(from)),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Text('To', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: pickTo,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(fmt(to)),
                    ),
                  ),

                  if (!valid) ...[
                    const SizedBox(height: 8),
                    Text(
                      'From date must be on or before To date.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.red),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: valid
                            ? () => Navigator.pop(ctx, DateTimeRange(start: from, end: to))
                            : null,
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _onShareTapped() async {
    final picked = await _pickRangeSimple(context);
    if (picked == null) return;

    _selectedRange = picked;
    if (!mounted) return;

    // Choose format (CSV now, PDF later)
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Export as CSV (editable)'),
              onTap: () => Navigator.pop(ctx, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Export as PDF (read-only) — coming soon'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == 'csv') {
      await _exportCsv(picked);
    } else if (choice == 'pdf') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF export will be added soon')),
        );
      }
    }
  }

  Future<void> _exportCsv(DateTimeRange range) async {
    setState(() => _exporting = true);
    try {
      final filtered = _entries.where((e) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        final s = DateTime(range.start.year, range.start.month, range.start.day);
        final t = DateTime(range.end.year, range.end.month, range.end.day);
        return (d.isAtSameMomentAs(s) || d.isAfter(s)) && (d.isAtSameMomentAs(t) || d.isBefore(t));
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      // Compute total time
      int totalMinutes = 0;
      for (final e in filtered) {
        totalMinutes += (e.hours * 60) + e.minutes;
      }
      final th = totalMinutes ~/ 60;
      final tm = totalMinutes % 60;

      // Build CSV with a human header then spreadsheet rows
      final sb = StringBuffer();
      final fromStr = formatDate(range.start, _fmt).replaceAll(',', ' ');
      final toStr = formatDate(range.end, _fmt).replaceAll(',', ' ');
      sb.writeln('"Name:",""'); // TODO: populate from settings when available
      sb.writeln('"Company:",""'); // TODO: populate from settings when available
      sb.writeln('"Email:",""'); // TODO: populate from settings when available
      sb.writeln('"Profession:","${widget.profession.replaceAll('"', '""')}"');
      sb.writeln('"Period:","$fromStr – $toStr"');
      sb.writeln('"Total Time:","${th}h ${tm}m"');
      sb.writeln('');
      sb.writeln('Date,Title,Hours,Minutes,Details,Attachments');
      for (final e in filtered) {
        final dateStr = formatDate(e.date, _fmt).replaceAll(',', ' ');
        final title = e.title.replaceAll('"', '""');
        final details = e.details.replaceAll('\n', ' ').replaceAll('"', '""');
        final attachments = e.attachments.join('|').replaceAll('"', '""');
        sb.writeln('"$dateStr","$title",${e.hours},${e.minutes},"$details","$attachments"');
      }

      // Write to a temp file
      final dir = await getTemporaryDirectory();
      final safeProf = widget.profession.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      final ts = DateTime.now();
      final tsStr = '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}';
      final path = '${dir.path}/cpd_${safeProf}_$tsStr.csv';
      final file = File(path);
      await file.writeAsBytes(utf8.encode(sb.toString()), flush: true);

      // Share sheet (email/messages/WhatsApp/etc). The file is an attachment.
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: file.uri.pathSegments.last)],
        text: 'CPD entries for ${widget.profession} ($fromStr to $toStr) — Total ${th}h ${tm}m',
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.profession)),
      body: _entries.isEmpty
          ? const Center(child: Text('No CPD records yet.'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final e = _entries[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row + per-record menu
                        Row(
                          children: [
                            Expanded(
                              child: Text(e.title, style: Theme.of(context).textTheme.titleMedium),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _edit(e);
                                if (value == 'delete') _toggleDelete(e);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit record')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(e.deleted ? 'Restore record' : 'Delete record'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatDate(e.date, _fmt)}   ${e.hours}h ${e.minutes}m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(e.details),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () => _showAttachments(e),
                            icon: const Icon(Icons.attachment),
                            label: const Text('Attachments'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Share / Export',
              onPressed: _entries.isEmpty ? null : _onShareTapped,
              icon: const Icon(Icons.ios_share),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}