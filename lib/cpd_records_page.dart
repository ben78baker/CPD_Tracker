import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'entry_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'add_entry_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'utils/attachment_io.dart';
import 'widgets/period_picker.dart' show showPeriodPicker;
import 'utils/date_utils.dart';
import 'utils/csv_exporter.dart';
import 'utils/pdf_exporter.dart';
import 'widgets/record_card.dart';
import 'widgets/attachments_dialog.dart';
import 'widgets/share_format_sheet.dart';

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
  bool _exporting = false;
  DateTimeRange? _lastRange; // NEW: remember picked range

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

  Future<void> _shareAttachmentPath(String path) async {
    try {
      if (isUrl(path)) {
        await SharePlus.instance.share(
          ShareParams(
            text: path.trim(),
            subject: 'CPD link',
          ),
        );
        return;
      }
      if (await File(path).exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                path,
                // mimeType optional; let the platform infer
                name: p.basename(path),
              ),
            ],
            subject: 'CPD attachment',
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File not found.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }

  Future<DateTimeRange?> _pickRangeSimple(BuildContext context) async {
    if (_entries.isEmpty) return null;

    // Determine bounds from dataset
    DateTime minD = DateTime(9999);
    DateTime maxD = DateTime(0);
    for (final e in _entries) {
      final d = dateOnly(e.date);
      if (d.isBefore(minD)) minD = d;
      if (d.isAfter(maxD)) maxD = d;
    }

    // Use shared bottom sheet (now with date captions)
    return await showPeriodPicker(
      context: context,
      initialFrom: minD,
      initialTo: maxD,
      dateFormat: _fmt,
    );
  }

  Future<void> _onShareTapped() async {
    final picked = await _pickRangeSimple(context);
    if (picked == null) return;
    setState(() => _lastRange = picked); // NEW: store to show in AppBar

    if (!mounted) return;

    // Choose format via shared sheet (CSV now, PDF later)
    final choice = await showShareFormatSheet(context);

    debugPrint('Share format choice: $choice');
    if (choice == null) {
      debugPrint('Share/Export sheet dismissed');
      return;
    }

    final sel = choice.trim().toLowerCase();
    debugPrint('Normalized share format choice: ' + sel);

    final hasAny = _entries.any((e) {
      final d = dateOnly(e.date);
      final s = dateOnly(picked.start);
      final t = dateOnly(picked.end);
      return !d.isBefore(s) && !d.isAfter(t);
    });
    if (!hasAny) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No records in the selected period.')),
        );
      }
      return;
    }

    if (sel == 'csv') {
      setState(() => _exporting = true);
      try {
        debugPrint('Exporting CSV for ${widget.profession} range ${picked.start} – ${picked.end}');
        await exportRecordsCsv(
          context: context,
          profession: widget.profession,
          dateFormat: _fmt,
          entries: _entries,
          range: picked,
        );
      } catch (err, st) {
        debugPrint('CSV export failed: $err');
        debugPrint(st.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $err')),
          );
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    } else if (sel == 'pdf') {
      setState(() => _exporting = true);
      // Load user profile (name/company/email) from SettingsStore
      final Map<String, String> profile = await _settings.loadProfile();
      final String userName = profile['name']?.trim() ?? '';
      final String company  = profile['company']?.trim() ?? '';
      final String email    = profile['email']?.trim() ?? '';
      try {
        debugPrint('Exporting PDF for ${widget.profession} range ${picked.start} – ${picked.end}');
        await exportRecordsPdf(
          profession: widget.profession,
          entries: _entries,
          range: picked,
          userName: userName,
          company: company,
          email: email,
          includeAttachments: true,
        );
      } catch (err, st) {
        debugPrint('PDF export failed: $err');
        debugPrint(st.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $err')),
          );
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    } else if (sel == 'pdf_bundle') {
      setState(() => _exporting = true);
      final Map<String, String> profile = await _settings.loadProfile();
      final String userName = profile['name']?.trim() ?? '';
      final String company  = profile['company']?.trim() ?? '';
      final String email    = profile['email']?.trim() ?? '';
      try {
        debugPrint('Exporting PDF Bundle for ${widget.profession} range ${picked.start} – ${picked.end}');
        await exportRecordsBundleZip(
          profession: widget.profession,
          entries: _entries,
          range: picked,
          userName: userName,
          company: company,
          email: email,
        );
      } catch (err, st) {
        debugPrint('PDF Bundle export failed: $err');
        debugPrint(st.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $err')),
          );
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    } else {
      debugPrint('Unknown share format returned: ' + sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.profession),
            if (_lastRange != null)
              Text(
                'Period: ${formatDate(_lastRange!.start, _fmt)} – ${formatDate(_lastRange!.end, _fmt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('No CPD records yet.'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final e = _entries[i];
                return RecordCard(
                  entry: e,
                  dateFormat: _fmt,
                  onEdit: () => _edit(e),
                  onDelete: () => _toggleDelete(e),
                  onViewAttachments: () => showAttachmentsDialog(
                    context: context,
                    attachments: e.attachments,
                    title: 'Attachments',
                    enableLongPressActions: true,
                    onShareOne: (path) => _shareAttachmentPath(path),
                    onRemoveIndex: (idx) async {
                      if (idx < 0 || idx >= e.attachments.length) return;
                      // Remove from the model and persist
                      e.attachments.removeAt(idx);
                      await _repo.updateEntry(e);
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Attachment removed.')),
                        );
                      }
                    },
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
              onPressed: (_entries.isEmpty || _exporting) ? null : _onShareTapped,
              icon: const Icon(Icons.ios_share),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}