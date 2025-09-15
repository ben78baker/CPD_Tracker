import 'dart:io';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models.dart';

/// Builds a landscape PDF summarising [entries].
/// If [includeAttachments] is true, a second section is appended that
/// renders thumbnails for image attachments and lists non‑image files/URLs.
Future<File> buildRecordsPdf({
  required String profession,
  required List<CpdEntry> entries,
  DateTimeRange? range,
  String? userName,
  String? company,
  String? email,
  bool includeAttachments = false,
}) async {
  final doc = pw.Document();

  // Normalise & sort by date ascending
  final list = [...entries]..sort((a, b) => a.date.compareTo(b.date));

  // Header helpers
  String periodText() {
    if (range == null) return 'All time';
    return '${formatDate(range!.start, 'dd/MM/yyyy')} to ${formatDate(range!.end, 'dd/MM/yyyy')}';
  }

  String totalText() {
    int th = 0, tm = 0;
    for (final e in list) {
      th += e.hours;
      tm += e.minutes;
    }
    th += tm ~/ 60; tm = tm % 60;
    return '${th}h ${tm}m';
  }

  // ===== Index page(s) – grouped per record with mini headers =====
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      build: (ctx) {
        final rows = <pw.Widget>[];

        rows.add(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CPD Records', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              if ((userName ?? '').isNotEmpty) pw.Text(userName!),
              if ((company ?? '').isNotEmpty) pw.Text(company!),
              if ((email ?? '').isNotEmpty) pw.Text(email!),
              pw.SizedBox(height: 8),
              pw.Text('Profession: $profession'),
              pw.Text('Period: ${periodText()}'),
              pw.Text('Total Time: ${totalText()}'),
              pw.SizedBox(height: 12),
            ],
          ),
        );

        for (final e in list) {
          final dateStr = formatDate(e.date, 'dd/MM/yyyy');
          final hh = e.hours.toString();
          final mm = e.minutes.toString();

          rows.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Inline header: date + title (left), attachment notice (right when present)
                  () {
                    final hasAtt = e.attachments.isNotEmpty;
                    return pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            '$dateStr  -  ${e.title}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        if (hasAtt)
                          pw.Text(
                            includeAttachments
                                ? 'Attachments/Evidence below'
                                : 'Attachments/Evidence available on request',
                            style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
                          ),
                      ],
                    );
                  }(),
                  pw.SizedBox(height: 4),
                  // Details-focused table (no attachments column)
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    headers: const ['Hours', 'Minutes', 'Details'],
                    data: [
                      [hh, mm, e.details ?? ''],
                    ],
                    cellAlignment: pw.Alignment.centerLeft,
                    columnWidths: {
                      0: const pw.FlexColumnWidth(0.9),
                      1: const pw.FlexColumnWidth(1.0),
                      2: const pw.FlexColumnWidth(4.0), // details gets priority width
                    },
                  ),
                ],
              ),
            ),
          );
        }

        return rows;
      },
    ),
  );

  // ===== Optional attachment appendix (thumbnails) =====
  if (includeAttachments) {
    // Build a flat list of attachment entries with pointer to record title/date
    final att = <_Att>[];
    for (final e in list) {
      for (final a in e.attachments) {
        att.add(_Att(entryTitle: e.title, entryDate: e.date, pathOrUrl: a));
      }
    }

    if (att.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) {
            final widgets = <pw.Widget>[
              pw.Text('Attachments', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
            ];

            // Render each as a card; images get thumbnails, others get a filename row
            for (final a in att) {
              final isImg = _looksLikeImage(a.pathOrUrl);
              pw.Widget preview;
              if (isImg && _fileExistsSync(a.pathOrUrl)) {
                try {
                  final bytes = File(a.pathOrUrl).readAsBytesSync();
                  preview = pw.Image(pw.MemoryImage(bytes), height: 120, fit: pw.BoxFit.contain);
                } catch (_) {
                  preview = _fileRow(a.pathOrUrl);
                }
              } else {
                preview = _fileRow(a.pathOrUrl);
              }

              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 10),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('${formatDate(a.entryDate, 'dd/MM/yyyy')} - ${a.entryTitle}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 6),
                      preview,
                    ],
                  ),
                ),
              );
            }

            return widgets;
          },
        ),
      );
    }
  }

  final tmp = await _saveTemp(doc, _makeFileName(profession, range));
  return tmp;
}

/// Convenience: build the PDF then invoke the platform share sheet.
Future<void> exportRecordsPdf({
  required String profession,
  required List<CpdEntry> entries,
  DateTimeRange? range,
  String? userName,
  String? company,
  String? email,
  bool includeAttachments = false,
}) async {
  final file = await buildRecordsPdf(
    profession: profession,
    entries: entries,
    range: range,
    userName: userName,
    company: company,
    email: email,
    includeAttachments: includeAttachments,
  );

  final filename = p.basename(file.path);
  await SharePlus.instance.share(
    ShareParams(
      subject: 'CPD records',
      text: 'CPD records',
      files: [XFile(file.path, mimeType: 'application/pdf', name: filename)],
    ),
  );
}

// ----------------- helpers -----------------

String _safeFileName(String input) {
  // Replace characters that are illegal on common filesystems
  final s = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  // Collapse whitespace to single underscores
  return s.replaceAll(RegExp(r'\s+'), '_');
}

String _dateToken(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

String _makeFileName(String profession, DateTimeRange? r) {
  final now = DateTime.now();
  final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

  final period = (r == null)
      ? ''
      : '_${_dateToken(r.start)}-${_dateToken(r.end)}';

  final safeProfession = _safeFileName(profession);
  return 'cpd_records_${safeProfession}${period}_$stamp.pdf';
}

Future<File> _saveTemp(pw.Document doc, String fileName) async {
  final bytes = await doc.save();
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, fileName));
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

String _attachmentLabel(String a) {
  if (a.startsWith('http://') || a.startsWith('https://')) return a;
  return p.basename(a);
}

bool _looksLikeImage(String pth) {
  final ext = p.extension(pth).toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic'].contains(ext);
}

bool _fileExistsSync(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

pw.Widget _fileRow(String pathOrUrl) => pw.Text(_attachmentLabel(pathOrUrl));

class _Att {
  _Att({required this.entryTitle, required this.entryDate, required this.pathOrUrl});
  final String entryTitle;
  final DateTime entryDate;
  final String pathOrUrl;
}
