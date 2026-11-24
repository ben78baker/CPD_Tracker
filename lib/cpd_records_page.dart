import 'package:flutter/material.dart';
import 'dart:io';
import 'cpd_compatibility/cpd_data_store.dart';
import 'cpd_compatibility/cpd_records_source.dart';
import 'cpd_compatibility/report_locale.dart';
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
import 'utils/csv_exporter.dart';
import 'utils/pdf_exporter.dart';
import 'widgets/record_card.dart';
import 'widgets/attachments_dialog.dart';
import 'widgets/share_format_sheet.dart';
import 'widgets/branded_headers.dart';
import 'widgets/tactile_button.dart';
import 'l10n/app_localizations.dart';

class CpdRecordsPage extends StatefulWidget {
  static const schemeReportFormat = 'scheme_report';

  const CpdRecordsPage({
    super.key,
    required this.profession,
    this.startInSearchMode = false,
    this.initialSearchQuery = '',
    this.recordStore,
    this.source,
    this.professionId,
    this.onOpenRecord,
    this.onEditFields,
    this.additionalFormats = const {},
    this.onAdditionalExport,
  }) : assert(source == null || (professionId != null && onOpenRecord != null));
  final String profession;
  final bool startInSearchMode;
  final String initialSearchQuery;
  final CpdRecordStore? recordStore;
  final CpdRecordsSource? source;
  final String? professionId;
  final Future<void> Function(CpdRecordItem, {required bool view})?
  onOpenRecord;
  final Future<void> Function()? onEditFields;
  final Map<String, String> additionalFormats;
  final Future<void> Function(
    String format,
    List<CpdRecordItem> records,
    ReportLanguage language,
  )?
  onAdditionalExport;

  @override
  State<CpdRecordsPage> createState() => _CpdRecordsPageState();
}

class _CpdRecordsPageState extends State<CpdRecordsPage> {
  late final CpdRecordStore _repo = widget.recordStore ?? EntryRepository();
  final _settings = SettingsStore.instance;
  List<CpdRecordItem> _entries = [];
  late final TextEditingController _searchController;
  String _fmt = 'dd/MM/yyyy';
  bool _exporting = false;
  bool _openingRecord = false;
  bool _showSearch = false;
  String _searchQuery = '';
  DateTimeRange? _lastRange; // NEW: remember picked range

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery;
    _searchController = TextEditingController(text: _searchQuery);
    _showSearch =
        widget.startInSearchMode || widget.initialSearchQuery.trim().isNotEmpty;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = widget.source;
    final list = source == null
        ? (await _repo.loadForProfession(
            widget.profession,
          )).map(CpdRecordItem.legacy).toList()
        : await source.records(professionId: widget.professionId!);
    list.sort((a, b) => b.entry.date.compareTo(a.entry.date));
    final fmt = source == null
        ? await _settings.getDateFormat()
        : (await source.preferences())['dateFormat'] ?? 'dd/MM/yyyy';
    if (!mounted) return;
    setState(() {
      _entries = list;
      _fmt = fmt;
    });
  }

  List<CpdRecordItem> get _filteredEntries =>
      _entries.where((record) => record.matches(_searchQuery)).toList();

  Future<void> _open(CpdRecordItem item, {bool view = false}) async {
    if (_openingRecord) return;
    _openingRecord = true;
    try {
      if (widget.onOpenRecord case final open?) {
        await open(item, view: view);
      } else {
        final e = item.entry;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddEntryPage(
              profession: e.profession,
              existingEntry: e,
              recordStore: _repo,
            ),
          ),
        );
      }
      if (mounted) await _load();
    } finally {
      _openingRecord = false;
    }
  }

  void _toggleSearch() {
    setState(() {
      if (_showSearch) {
        _showSearch = false;
        _searchQuery = '';
        _searchController.clear();
      } else {
        _showSearch = true;
      }
    });
  }

  Future<void> _toggleDelete(CpdRecordItem item) async {
    final e = item.entry;
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
          TactileButton(
            onPressed: () => Navigator.pop(ctx, true),
            variant: e.deleted
                ? TactileButtonVariant.primary
                : TactileButtonVariant.destructive,
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
    if (widget.source case final source?) {
      try {
        await source.setDeleted(item, !e.deleted);
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.recordChangeFailed),
            ),
          );
        }
      }
    } else {
      await _repo.setDeleted(e.id, !e.deleted);
    }
    if (mounted) await _load();
  }

  Future<void> _shareAttachmentPath(String path, {String? displayName}) async {
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
                name: displayName ?? p.basename(resolvedPath),
              ),
            ],
            fileNameOverrides: displayName == null
                ? null
                : [p.basename(displayName)],
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

  Future<void> _showAttachments(CpdRecordItem item) async {
    final e = item.entry;
    final loc = AppLocalizations.of(context)!;
    final source = widget.source;
    if (source == null) {
      await showAttachmentsDialog(
        context: context,
        attachments: e.attachments,
        title: loc.attachments,
        onShareOne: _shareAttachmentPath,
        onRemoveIndex: (idx) async {
          if (idx < 0 || idx >= e.attachments.length) return;
          e.attachments.removeAt(idx);
          await _repo.updateEntry(e);
          if (!mounted) return;
          setState(() {});
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.attachmentRemoved)));
        },
      );
      return;
    }

    var version = item.version;
    var evidence = item.evidence;
    await showAttachmentsDialog(
      context: context,
      attachments: e.attachments,
      displayNames: evidence.map((item) => item.label).toList(),
      title: loc.attachments,
      onShareAt: (index) {
        final asset = evidence[index];
        final target = asset.target;
        if (target == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.fileNotFoundWithName(asset.label))),
          );
          return Future.value();
        }
        return _shareAttachmentPath(target, displayName: asset.label);
      },
      onRemoveCurrent: (index) async {
        final removed = evidence[index];
        try {
          await source.unlinkEvidence(item.id, version, removed);
        } on Object {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(loc.recordChangeFailed)));
          }
          return false;
        }
        version++;
        evidence = [
          for (final (i, asset) in evidence.indexed)
            if (i != index)
              if (asset.fieldId == removed.fieldId &&
                  asset.ordinal > removed.ordinal)
                CpdEvidenceItem(
                  id: asset.id,
                  fieldId: asset.fieldId,
                  ordinal: asset.ordinal - 1,
                  label: asset.label,
                  target: asset.target,
                )
              else
                asset,
        ];
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.attachmentRemoved)));
        }
        return true;
      },
    );
    if (mounted) await _load();
  }

  Future<DateTimeRange?> _pickRangeSimple(BuildContext context) async {
    if (_entries.isEmpty) return null;

    // Determine bounds from dataset
    DateTime minD = DateTime(9999);
    DateTime maxD = DateTime(0);
    for (final e in _entries) {
      final d = dateOnly(e.entry.date);
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

  Future<void> _showPdfEvidenceOriginalsNotice() async {
    if (!mounted) return;
    await showPdfEvidenceOriginalsNotice(context);
  }

  Future<void> _onShareTapped() async {
    if (!mounted) return; // guard before async UI
    final picked = await _pickRangeSimple(context);
    if (!mounted) return; // guard after async UI
    if (picked == null) return;

    setState(() => _lastRange = picked); // remember picked range in AppBar

    final app = AppLocalizations.of(context)!;
    final source = widget.source;
    final savedLanguage = source == null
        ? await _settings.getReportLanguage()
        : ReportLanguage.fromStored(
            (await source.preferences())['reportLocale'],
          );
    var reportLanguage = savedLanguage;
    if (!mounted) return;
    final choice = await showShareFormatSheet(
      context,
      initialLanguage: savedLanguage,
      additionalFormats: widget.additionalFormats,
      onReportLanguageChanged: (choice) => reportLanguage = choice,
    );
    if (!mounted) return;

    Future<PdfExportTexts> pdfTexts() async {
      if (reportLanguage == ReportLanguage.app) {
        return PdfExportTexts.fromLoc(app);
      }
      final locale = await ReportLocale.resolve(reportLanguage, app);
      return PdfExportTexts.fromLoc(locale.strings, reportLocale: locale);
    }

    debugPrint('Share format choice: $choice');
    if (choice == null) {
      debugPrint('Share/Export sheet dismissed');
      return;
    }

    if (savedLanguage != reportLanguage) {
      try {
        if (source == null) {
          await _settings.setReportLanguage(reportLanguage);
        } else {
          await source.setReportLanguage(reportLanguage);
        }
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(app.editorSaveError)));
        return;
      }
      if (!mounted) return;
    }
    final sel = choice.trim().toLowerCase();
    if (reportLanguage == ReportLanguage.hindi &&
        const {'pdf', 'pdf_evidence', 'pdf_bundle'}.contains(sel)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.reportHindiRequiresShaping)));
      return;
    }
    debugPrint('Normalized share format choice: $sel');

    final visible = _filteredEntries;
    final exportSelection = CpdExportSelection.fromVisibleRecords(
      profession: widget.profession,
      range: picked,
      visibleRecords: visible.map((row) => row.entry),
      evidenceNames: {
        for (final row in visible)
          if (row.evidence.isNotEmpty)
            row.entry.id: row.evidence.map((asset) => asset.label).toList(),
      },
    );
    if (sel == CpdRecordsPage.schemeReportFormat &&
        widget.onAdditionalExport != null) {
      await _exportAdditional(sel, List.of(_entries), reportLanguage);
      return;
    }
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

    if (widget.additionalFormats.containsKey(sel) &&
        widget.onAdditionalExport != null) {
      final selected = exportSelection.records.toSet();
      await _exportAdditional(
        sel,
        visible.where((row) => selected.contains(row.entry)).toList(),
        reportLanguage,
      );
      return;
    }

    if (sel == 'csv') {
      if (!mounted) return;
      setState(() => _exporting = true);
      // Load user profile (name/company/email) from SettingsStore
      final Map<String, String> profile = await _loadProfile();
      if (!mounted) return;
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
      final Map<String, String> profile = await _loadProfile();
      if (!mounted) return;
      final String userName = profile['name']?.trim() ?? '';
      final String company = profile['company']?.trim() ?? '';
      final String address = profile['address']?.trim() ?? '';
      final String email = profile['email']?.trim() ?? '';
      try {
        debugPrint(
          'Exporting PDF for ${widget.profession} range ${picked.start} – ${picked.end}',
        );
        final texts = await pdfTexts();
        await exportRecordsPdf(
          selection: exportSelection,
          dateFormat: _fmt,
          userName: userName,
          company: company,
          address: address,
          email: email,
          texts: texts,
          evidenceMode: sel == 'pdf_evidence'
              ? CpdPdfEvidenceMode.embeddedImages
              : CpdPdfEvidenceMode.textOnly,
          onOriginalEvidenceBundleReady: sel == 'pdf_evidence'
              ? _showPdfEvidenceOriginalsNotice
              : null,
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
      final Map<String, String> profile = await _loadProfile();
      if (!mounted) return;
      final String userName = profile['name']?.trim() ?? '';
      final String company = profile['company']?.trim() ?? '';
      final String address = profile['address']?.trim() ?? '';
      final String email = profile['email']?.trim() ?? '';
      try {
        debugPrint(
          'Exporting PDF Bundle for ${widget.profession} range ${picked.start} – ${picked.end}',
        );
        final texts = await pdfTexts();
        await exportRecordsBundleZip(
          selection: exportSelection,
          dateFormat: _fmt,
          userName: userName,
          company: company,
          address: address,
          email: email,
          texts: texts,
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

  Future<Map<String, String>> _loadProfile() async {
    final source = widget.source;
    return source == null ? _settings.loadProfile() : source.preferences();
  }

  Future<void> _exportAdditional(
    String format,
    List<CpdRecordItem> records,
    ReportLanguage language,
  ) async {
    setState(() => _exporting = true);
    try {
      await widget.onAdditionalExport!(format, records, language);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.exportFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;
    return Scaffold(
      appBar: AppBar(
        bottom: _showSearch
            ? PreferredSize(
                preferredSize: const Size.fromHeight(68),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _searchController,
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
                                  _searchController.clear();
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
          if (widget.onEditFields case final editFields?)
            PopupMenuButton<String>(
              onSelected: (_) async {
                await editFields();
                if (mounted) await _load();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit_fields',
                  child: Text(AppLocalizations.of(context)!.editFields),
                ),
              ],
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
      body: Column(
        children: [
          BrandedPageHeader(
            title: widget.profession,
            icon: Icons.work_outline_rounded,
            subtitle: _lastRange == null
                ? null
                : '${AppLocalizations.of(context)!.periodLabel}: ${formatDate(_lastRange!.start, _fmt)} – ${formatDate(_lastRange!.end, _fmt)}',
          ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(AppLocalizations.of(context)!.noCpdRecordsYet),
                  )
                : filtered.isEmpty
                ? const Center(child: Text('No matching records found'))
                : ListView.builder(
                    key: const PageStorageKey('profession-records'),
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      return RecordCard(
                        key: ValueKey(item.id),
                        entry: item.entry,
                        dateFormat: _fmt,
                        onEdit: () => _open(item),
                        onView: widget.source == null
                            ? null
                            : () => _open(item, view: true),
                        onDelete: () => _toggleDelete(item),
                        onViewAttachments: () => _showAttachments(item),
                      );
                    },
                  ),
          ),
        ],
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
                onPressed: (filtered.isEmpty || _exporting)
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
