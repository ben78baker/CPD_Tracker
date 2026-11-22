import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cpd_tracker/cpd_backup/backup_cache.dart';
import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_editor/strings.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/record_export.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/utils/csv_exporter.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/utils/pdf_exporter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

Set<String> _attachmentIds(
  List<LayoutField> fields,
  Map<String, Object> values,
) => {
  for (final field in fields.where(
    (field) => field.definition.kind == FieldKind.attachments,
  ))
    ...((values[field.id] as List?)?.cast<String>() ?? const <String>[]),
};

enum _EvidenceSource { photo, file, link }

class RehearsalRecordFiles {
  RehearsalRecordFiles(this.repository, this.originals);
  final SqliteRecordingRepository repository;
  final ManagedAttachmentFiles? originals;
  final _pending = <String, RecordingAttachment>{};
  bool _closed = false;
  bool _picking = false;
  bool get picking => _picking;

  Map<String, String> get pendingLabels =>
      _pending.map((id, item) => MapEntry(id, item.name));

  Future<Map<String, String>> loadLabels(
    List<LayoutField> fields,
    Map<String, Object> values,
  ) async {
    final labels = <String, String>{};
    for (final id in _attachmentIds(fields, values)) {
      if (await repository.loadAttachment(id) case final attachment?) {
        labels[id] = attachment.name;
      }
    }
    return labels;
  }

  Future<String?> pick(BuildContext context, LayoutField field) async {
    if (_picking || _closed) return null;
    _picking = true;
    final s = editorStrings(context);
    try {
      final kind = await showModalBottomSheet<_EvidenceSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: Text(s.imageAttachment),
                onTap: () => Navigator.pop(context, _EvidenceSource.photo),
              ),
              if (field.format != FieldFormat.photograph)
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(s.fileAttachment),
                  onTap: () => Navigator.pop(context, _EvidenceSource.file),
                ),
              if (field.format != FieldFormat.photograph)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(s.link),
                  onTap: () => Navigator.pop(context, _EvidenceSource.link),
                ),
            ],
          ),
        ),
      );
      if (kind == null || _closed || !context.mounted) return null;
      if (kind == _EvidenceSource.link) return await _pickLink(context);
      final result = await FilePicker.platform.pickFiles(
        type: kind == _EvidenceSource.photo ? FileType.image : FileType.any,
      );
      if (result == null || result.files.single.path == null) return null;
      final picked = result.files.single;
      final owner = Platform.isAndroid
          ? Directory(
              p.join((await getTemporaryDirectory()).path, 'file_picker'),
            )
          : Directory.systemTemp;
      final input = BackupInputFile(
        File(picked.path!),
        cacheRoot: owner,
        nestedCache: Platform.isAndroid,
      );
      try {
        if (_closed) return null;
        final attachment = await originals!.copyOriginal(
          input.file,
          displayName: picked.name,
          importId: const Uuid().v4(),
        );
        if (_closed) {
          await (await originals!.resolveOriginal(attachment))?.delete();
          return null;
        }
        _pending[attachment.id] = attachment;
        return attachment.id;
      } finally {
        await input.dispose();
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.attachmentFailed)));
      }
      return null;
    } finally {
      _picking = false;
    }
  }

  Future<String?> _pickLink(BuildContext context) async {
    final s = editorStrings(context);
    var entered = '';
    final url = await showDialog<Uri>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.link),
        content: TextField(
          decoration: InputDecoration(labelText: s.editorLink),
          keyboardType: TextInputType.url,
          autofocus: true,
          onChanged: (value) => entered = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () {
              final uri = Uri.tryParse(entered.trim());
              if (uri != null &&
                  ['https', 'http'].contains(uri.scheme) &&
                  uri.host.isNotEmpty) {
                Navigator.pop(context, uri);
              }
            },
            child: Text(s.add),
          ),
        ],
      ),
    );
    if (url == null || _closed) return null;
    final id = const Uuid().v4();
    _pending[id] = RecordingAttachment(
      id: id,
      kind: AttachmentKind.link,
      locator: url.toString(),
      name: url.host,
    );
    return id;
  }

  List<RecordingAttachment> linked(
    List<LayoutField> fields,
    Map<String, Object> values,
  ) => [for (final id in _attachmentIds(fields, values)) ?_pending[id]];

  Future<void> open(BuildContext context, String id) async {
    final s = editorStrings(context);
    try {
      final item = _pending[id] ?? await repository.loadAttachment(id);
      if (item == null) throw StateError('Attachment unavailable.');
      if (item.kind == AttachmentKind.managed) {
        final file = await originals?.resolveOriginal(item);
        if (file == null) throw StateError('Attachment unavailable.');
        if ((await OpenFilex.open(file.path)).type == ResultType.done) return;
      }
      if (item.kind == AttachmentKind.link) {
        final uri = Uri.tryParse(item.locator);
        if (uri != null &&
            ['https', 'http'].contains(uri.scheme) &&
            await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      }
      throw StateError('Attachment unavailable.');
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.unableToOpenAttachment)));
      }
    }
  }

  Future<void> dispose() async {
    _closed = true;
    for (final item in _pending.values) {
      try {
        if (await repository.loadAttachment(item.id) == null) {
          await (await originals?.resolveOriginal(item))?.delete();
        }
      } on Object {
        // Backup reconciliation retries at cold start with the store open.
      }
    }
  }
}

/// The ordinary exports are independent of trial status. The legacy exporters
/// keep their PDF/evidence compatibility, and the field CSV carries all values.
class RehearsalExportActions extends StatelessWidget {
  const RehearsalExportActions({
    super.key,
    required this.store,
    required this.profession,
    required this.history,
    required this.records,
    this.originals,
  });

  final ProfessionCreationStore store;
  final RecordingCollection profession;
  final List<LayoutRevision> history;
  final List<RecordingRecord> records;
  final ManagedAttachmentFiles? originals;

  Future<CpdExportSelection> _ordinary() async {
    final entries = <CpdEntry>[];
    for (final (index, record) in records.indexed) {
      if (record.deleted) continue;
      final fields = resolveFields(record.layoutVersion, history);
      final binding = cpdFieldBindings(fields);
      final evidence = <String>[];
      for (final id in _attachmentIds(fields, record.values)) {
        final attachment = await store.repository.loadAttachment(id);
        if (attachment == null) continue;
        if (attachment.kind == AttachmentKind.link) {
          evidence.add(attachment.locator);
        } else {
          final file = await originals?.resolveOriginal(attachment);
          evidence.add(
            file?.path ??
                p.join(
                  Directory.systemTemp.path,
                  'unavailable-$id',
                  p.basename(attachment.name),
                ),
          );
        }
      }
      final total = record.values[binding['cpd.creditedDuration']] as int? ?? 0;
      entries.add(
        CpdEntry(
          id: index + 1,
          profession: profession.label,
          date: DateTime.parse(
            record.values[binding['cpd.activityDate']] as String,
          ),
          title: record.values[binding['cpd.title']] as String? ?? '',
          details: record.values[binding['cpd.details']] as String? ?? '',
          hours: total ~/ 60,
          minutes: total % 60,
          attachments: evidence,
        ),
      );
    }
    final dates = entries.map((entry) => entry.date).toList()..sort();
    return CpdExportSelection.fromVisibleRecords(
      profession: profession.label,
      range: DateTimeRange(start: dates.first, end: dates.last),
      visibleRecords: entries,
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(editorStrings(context).exportFailed)),
        );
      }
    }
  }

  Future<void> _fieldsCsv(BuildContext context) async {
    final bounds = context.findRenderObject()! as RenderBox;
    final anchor = bounds.localToGlobal(Offset.zero) & bounds.size;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rows = [
      recordExportHeader,
      for (final record in records.where((record) => !record.deleted))
        ...recordExportRows(
          record,
          resolveFields(record.layoutVersion, history),
          locale: locale,
        ),
    ];
    final csv = rows
        .map(
          (row) => row
              .map((cell) {
                final safe = RegExp(r'^\s*[=+@-]').hasMatch(cell)
                    ? "'$cell"
                    : cell;
                return '"${safe.replaceAll('"', '""')}"';
              })
              .join(','),
        )
        .join('\r\n');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(csv)),
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: ['CPD-fields.csv'],
        sharePositionOrigin: anchor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    const format = 'dd/MM/yyyy';
    return Wrap(
      children: [
        TextButton(
          onPressed: () => _run(context, () async {
            final selection = await _ordinary();
            if (context.mounted) {
              await exportRecordsCsv(
                context: context,
                selection: selection,
                dateFormat: format,
              );
            }
          }),
          child: Text(s.csvEditable),
        ),
        TextButton(
          onPressed: () => _run(context, () => _fieldsCsv(context)),
          child: Text('${s.csvEditable} · ${s.editFields}'),
        ),
        for (final (mode, label) in [
          (CpdPdfEvidenceMode.textOnly, s.pdfWithoutEvidence),
          (CpdPdfEvidenceMode.embeddedImages, s.pdfWithEvidence),
        ])
          TextButton(
            onPressed: () => _run(context, () async {
              await exportRecordsPdf(
                selection: await _ordinary(),
                dateFormat: format,
                texts: PdfExportTexts.fromLoc(s),
                evidenceMode: mode,
              );
            }),
            child: Text(label),
          ),
        TextButton(
          onPressed: () => _run(context, () async {
            await exportRecordsBundleZip(
              selection: await _ordinary(),
              dateFormat: format,
              texts: PdfExportTexts.fromLoc(s),
            );
          }),
          child: Text(s.pdfAttachmentsBundle),
        ),
      ],
    );
  }
}
