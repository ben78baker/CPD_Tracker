import 'package:flutter/material.dart';
import 'dart:io';
import 'entry_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'add_entry_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'utils/attachment_io.dart';
import 'utils/export_selection.dart';
import 'widgets/period_picker.dart' show showPeriodPicker;
import 'utils/date_utils.dart';
import 'utils/record_search.dart';
import 'utils/csv_exporter.dart';
import 'utils/pdf_exporter.dart';
import 'widgets/record_card.dart';
import 'widgets/attachments_dialog.dart';
import 'widgets/share_format_sheet.dart';
import 'l10n/app_localizations.dart';

class CpdRecordsPage extends StatefulWidget {
  const CpdRecordsPage({
    super.key,
    required this.profession,
    this.startInSearchMode = false,
    this.initialSearchQuery = '',
  });
  final String profession;
  final bool startInSearchMode;
  final String initialSearchQuery;

  @override
  State<CpdRecordsPage> createState() => _CpdRecordsPageState();
}

class _CpdRecordsPageState extends State<CpdRecordsPage> {
  final _repo = EntryRepository();
  final _settings = SettingsStore.instance;
  List<CpdEntry> _entries = [];
  String _fmt = 'dd/MM/yyyy';
  bool _exporting = false;
  bool _showSearch = false;
  String _searchQuery = '';
  DateTimeRange? _lastRange; // NEW: remember picked range

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery;
    _showSearch =
        widget.startInSearchMode || widget.initialSearchQuery.trim().isNotEmpty;
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

  List<CpdEntry> get _filteredEntries {
    return RecordSearch.filter(_entries, _searchQuery);
  }

  Future<void> _edit(CpdEntry e) async {
    if (!mounted) return; // guard before using context
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AddEntryPage(profession: e.profession, existingEntry: e),
      ),
    );
    if (!mounted) return; // guard after the await
    _load();
  }

  void _toggleSearch() {
    setState(() {
      if (_showSearch) {
        _showSearch = false;
        _searchQuery = '';
      } else {
        _showSearch = true;
      }
    });
  }

  Future<void> _toggleDelete(CpdEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          e.deleted
              ? AppLocalizations.of(ctx)!.restoreRecordTitle
              : AppLocalizations.of(ctx)!.deleteRecordTitle,
        ),
        content: Text(
          e.deleted
              ? AppLocalizations.of(ctx)!.restoreRecordConfirm
              : AppLocalizations.of(ctx)!.deleteRecordConfirm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              e.deleted
                  ? AppLocalizations.of(ctx)!.restore
                  : AppLocalizations.of(ctx)!.delete,
            ),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (confirm != true) return;
    await _repo.setDeleted(e.id, !e.deleted);
    if (!mounted) return;
    _load();
  }

  Future<void> _shareAttachmentPath(String path) async {
    try {
      if (isUrl(path)) {
        await SharePlus.instance.share(
          ShareParams(
            text: path.trim(),
            subject: AppLocalizations.of(context)!.cpdLinkSubject,
          ),
        );
        return;
      }
      final resolvedPath = await resolveStoredPath(path);
      if (!mounted) return;
      final exists = await File(resolvedPath).exists();
      if (!mounted) return;
      if (exists) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                resolvedPath,
                // mimeType optional; let the platform infer
                name: p.basename(resolvedPath),
              ),
            ],
            subject: AppLocalizations.of(context)!.cpdAttachmentSubject,
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.fileNotFound)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.shareFailed}: $e'),
          ),
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
    if (!mounted) return; // guard before async UI
    final picked = await _pickRangeSimple(context);
    if (!mounted) return; // guard after async UI
    if (picked == null) return;

    setState(() => _lastRange = picked); // remember picked range in AppBar

    // Choose format via shared sheet (CSV now, PDF later)
    if (!mounted) return; // guard before async UI
    final choice = await showShareFormatSheet(context);
    if (!mounted) return; // guard after async UI

    debugPrint('Share format choice: $choice');
    if (choice == null) {
      debugPrint('Share/Export sheet dismissed');
      return;
    }

    final sel = choice.trim().toLowerCase();
    debugPrint('Normalized share format choice: $sel');

    final exportSelection = CpdExportSelection.fromVisibleRecords(
      profession: widget.profession,
      range: picked,
      visibleRecords: _filteredEntries,
    );
    if (exportSelection.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.noRecordsInSelectedPeriod,
            ),
          ),
        );
      }
      return;
    }

    if (sel == 'csv') {
      if (!mounted) return;
      setState(() => _exporting = true);
      // Load user profile (name/company/email) from SettingsStore
      final Map<String, String> profile = await _settings.loadProfile();
      final String userName = profile['name']?.trim() ?? '';
      final String company = profile['company']?.trim() ?? '';
      final String email = profile['email']?.trim() ?? '';
      try {
        debugPrint(
          'Exporting CSV for ${widget.profession} range ${picked.start} – ${picked.end}',
        );
        await exportRecordsCsv(
          context: context,
          selection: exportSelection,
          dateFormat: _fmt,
          userName: userName,
          company: company,
          email: email,
        );
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route is PageRoute);
      } catch (err, st) {
        debugPrint('CSV export failed: $err');
        debugPrint(st.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppLocalizations.of(context)!.exportFailed}: $err',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    } else if (sel == 'pdf' || sel == 'pdf_evidence') {
      if (!mounted) return;
      setState(() => _exporting = true);
      // Load user profile (name/company/email) from SettingsStore
      final Map<String, String> profile = await _settings.loadProfile();
      final String userName = profile['name']?.trim() ?? '';
      final String company = profile['company']?.trim() ?? '';
      final String address = profile['address']?.trim() ?? '';
      final String email = profile['email']?.trim() ?? '';
      try {
        debugPrint(
          'Exporting PDF for ${widget.profession} range ${picked.start} – ${picked.end}',
        );
        final pdfTexts = PdfExportTexts.fromLoc(AppLocalizations.of(context)!);
        await exportRecordsPdf(
          selection: exportSelection,
          dateFormat: _fmt,
          userName: userName,
          company: company,
          address: address,
          email: email,
          texts: pdfTexts,
          evidenceMode: sel == 'pdf_evidence'
              ? CpdPdfEvidenceMode.embeddedImages
              : CpdPdfEvidenceMode.textOnly,
        );
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route is PageRoute);
      } catch (err, st) {
        debugPrint('PDF export failed: $err');
        debugPrint(st.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppLocalizations.of(context)!.exportFailed}: $err',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    } else if (sel == 'pdf_bundle') {
      if (!mounted) return;
      setState(() => _exporting = true);
      final Map<String, String> profile = await _settings.loadProfile();
      final String userName = profile['name']?.trim() ?? '';
      final String company = profile['company']?.trim() ?? '';
      final String address = profile['address']?.trim() ?? '';
      final String email = profile['email']?.trim() ?? '';
      try {
        debugPrint(
          'Exporting PDF Bundle for ${widget.profession} range ${picked.start} – ${picked.end}',
        );
        final pdfTexts = PdfExportTexts.fromLoc(AppLocalizations.of(context)!);
        await exportRecordsBundleZip(
          selection: exportSelection,
          dateFormat: _fmt,
          userName: userName,
          company: company,
          address: address,
          email: email,
          texts: pdfTexts,
        );
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route is PageRoute);
      } catch (err, st) {
        debugPrint('PDF Bundle export failed: $err');
        debugPrint(st.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppLocalizations.of(context)!.exportFailed}: $err',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    } else {
      debugPrint('Unknown share format returned: $sel');
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
                '${AppLocalizations.of(context)!.periodLabel}: ${formatDate(_lastRange!.start, _fmt)} – ${formatDate(_lastRange!.end, _fmt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        bottom: _showSearch
            ? PreferredSize(
                preferredSize: const Size.fromHeight(68),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    autofocus: true,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search records',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: _showSearch ? 'Close search' : 'Search records',
            onPressed: _toggleSearch,
            icon: Icon(_showSearch ? Icons.close : Icons.search),
          ),
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
          ? Center(child: Text(AppLocalizations.of(context)!.noCpdRecordsYet))
          : _filteredEntries.isEmpty
          ? const Center(child: Text('No matching records found'))
          : ListView.builder(
              itemCount: _filteredEntries.length,
              itemBuilder: (context, i) {
                final e = _filteredEntries[i];
                return RecordCard(
                  entry: e,
                  dateFormat: _fmt,
                  onEdit: () => _edit(e),
                  onDelete: () => _toggleDelete(e),
                  onViewAttachments: () => showAttachmentsDialog(
                    context: context,
                    attachments: e.attachments,
                    title: AppLocalizations.of(context)!.attachments,
                    enableLongPressActions: true,
                    onShareOne: (path) => _shareAttachmentPath(path),
                    onRemoveIndex: (idx) async {
                      if (idx < 0 || idx >= e.attachments.length) return;
                      e.attachments.removeAt(idx);
                      await _repo.updateEntry(e);
                      if (!context.mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context)!.attachmentRemoved,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomAppBar(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: AppLocalizations.of(context)!.shareExport,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                visualDensity: VisualDensity.compact,
                onPressed:
                    (_entries.isEmpty || _filteredEntries.isEmpty || _exporting)
                    ? null
                    : _onShareTapped,
                icon: const Icon(Icons.ios_share, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
