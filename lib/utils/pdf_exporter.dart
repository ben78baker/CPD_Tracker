import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart'; // for debugPrint
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

  // Resolve stored attachment paths (relative or old absolute) to current container
  final docsDir = await getApplicationDocumentsDirectory();
  final docsPath = docsDir.path;
  String resolve(String stored) {
    if (stored.startsWith('http://') || stored.startsWith('https://')) return stored;
    if (stored.startsWith('/')) {
      final i = stored.indexOf('/Documents/');
      if (i != -1) {
        final tail = stored.substring(i + '/Documents/'.length);
        return p.join(docsPath, tail);
      }
      return stored;
    }
    return p.join(docsPath, stored);
  }
  debugPrint('[PDF] docsPath: $docsPath');

  // Header helpers
  String periodText() {
    if (range == null) return 'All time';
    return '${formatDate(range.start, 'dd/MM/yyyy')} to ${formatDate(range.end, 'dd/MM/yyyy')}';
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
              if ((userName ?? '').isNotEmpty) pw.Text(userName ?? ''),
              if ((company ?? '').isNotEmpty) pw.Text(company ?? ''),
              if ((email ?? '').isNotEmpty) pw.Text(email ?? ''),
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
                      [hh, mm, e.details],
                    ],
                    cellAlignment: pw.Alignment.centerLeft,
                    columnWidths: {
                      0: const pw.FlexColumnWidth(0.9),
                      1: const pw.FlexColumnWidth(1.0),
                      2: const pw.FlexColumnWidth(4.0), // details gets priority width
                    },
                  ),
                  // Inline attachments (images as thumbnails; others as names; URLs clickable)
                  if (e.attachments.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Attachments / Evidence:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    () {
                      final attWidgets = <pw.Widget>[];
                      for (final a in e.attachments) {
                        final resolved = resolve(a);
                        final exists = !_isUrl(a) && _fileExistsSync(resolved);
                        debugPrint('[PDF] att: $a -> $resolved exists=$exists');
                        if (_isUrl(a)) {
                          // Clickable web link
                          attWidgets.add(
                            pw.Container(
                              margin: const pw.EdgeInsets.only(right: 6, bottom: 6),
                              child: pw.UrlLink(
                                destination: a,
                                child: pw.Text(
                                  a,
                                  style: pw.TextStyle(color: PdfColors.blue, decoration: pw.TextDecoration.underline),
                                ),
                              ),
                            ),
                          );
                        } else if (_looksLikeImage(resolved) && _fileExistsSync(resolved)) {
                          // Local image thumbnail
                          try {
                            final bytes = File(resolved).readAsBytesSync();
                            attWidgets.add(
                              pw.Container(
                                margin: const pw.EdgeInsets.only(right: 6, bottom: 6),
                                width: 120,
                                height: 90,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(color: PdfColors.grey300),
                                  borderRadius: pw.BorderRadius.circular(3),
                                ),
                                child: pw.Padding(
                                  padding: const pw.EdgeInsets.all(2),
                                  child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
                                ),
                              ),
                            );
                          } catch (_) {
                            // Fallback to filename if image bytes cannot be read
                            final name = p.basename(resolved);
                            final size = _fileSizeSync(resolved);
                            final label = size == null ? name : '$name (${_prettySize(size)})';
                            attWidgets.add(pw.Text(label));
                          }
                        } else if (_fileExistsSync(resolved)) {
                          final name = p.basename(resolved);
                          final size = _fileSizeSync(resolved);
                          final label = size == null ? name : '$name (${_prettySize(size)})';
                          attWidgets.add(
                            pw.Container(
                              margin: const pw.EdgeInsets.only(right: 6, bottom: 6),
                              child: pw.Text(label),
                            ),
                          );
                        } else {
                          // Missing or unknown
                          attWidgets.add(
                            pw.Container(
                              margin: const pw.EdgeInsets.only(right: 6, bottom: 6),
                              child: pw.Text(p.basename(resolved)),
                            ),
                          );
                        }
                      }
                      return pw.Wrap(children: attWidgets);
                    }(),
                  ],
                ],
              ),
            ),
          );
        }

        return rows;
      },
    ),
  );

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

  // debug
  try {
    debugPrint('[PDF] path: ${file.path} (${await file.length()} bytes)');
  } catch (_) {}

  final filename = p.basename(file.path);
  await SharePlus.instance.share(
    ShareParams(
      subject: 'CPD records',
      files: [XFile(file.path, mimeType: 'application/pdf', name: filename)],
    ),
  );
}

/// Builds a ZIP bundle that contains the summary PDF **and** any local
/// attachments (images/docs) found in the selected records. URL attachments
/// are listed inside a small text file in the bundle.
Future<void> exportRecordsBundleZip({
  required String profession,
  required List<CpdEntry> entries,
  DateTimeRange? range,
  String? userName,
  String? company,
  String? email,
}) async {
  // 1) Build the summary PDF we already have
  final pdfFile = await buildRecordsPdf(
    profession: profession,
    entries: entries,
    range: range,
    userName: userName,
    company: company,
    email: email,
    includeAttachments: false,
  );

// Resolve stored attachment paths (relative or old absolute) to current container
final docsDir = await getApplicationDocumentsDirectory();
final docsPath = docsDir.path;
String resolve(String stored) {
  if (_isUrl(stored)) return stored;
  if (stored.startsWith('/')) {
    final i = stored.indexOf('/Documents/');
    if (i != -1) {
      final tail = stored.substring(i + '/Documents/'.length);
      return p.join(docsPath, tail);
    }
    return stored;
  }
  return p.join(docsPath, stored);
}

  // 2) Gather attachments
  final localPaths = <String>[];
  final urls = <String>[];
  for (final e in entries) {
    for (final a in e.attachments) {
      if (_isUrl(a)) {
       urls.add(a);
     } else {
       final resolved = resolve(a);
       if (_fileExistsSync(resolved)) localPaths.add(resolved);
     }
    }
  }

  debugPrint('[Bundle] locals: ${localPaths.length}, urls: ${urls.length}');

  // 3) Create ZIP archive
  final arch = Archive();

  // Add PDF summary
  arch.addFile(ArchiveFile.stream(
    p.basename(pdfFile.path),
    InputFileStream(pdfFile.path),
  ));

  // Add local attachments under attachments/
  for (final path in localPaths) {
    final nameInZip = p.join('attachments', p.basename(path));
    arch.addFile(ArchiveFile.stream(
      nameInZip,
      InputFileStream(path),
    ));
  }

  // Add link manifest if needed
  if (urls.isNotEmpty) {
    final buf = StringBuffer('CPD Attachment Links\n\n');
    if (range != null) {
      buf.writeln('Period: ${formatDate(range.start, 'dd/MM/yyyy')} to ${formatDate(range.end, 'dd/MM/yyyy')}\n');
    }
    for (final u in urls) {
      buf.writeln(u);
    }
    final manifestBytes = utf8.encode(buf.toString());
    arch.addFile(ArchiveFile('attachments/links.txt', manifestBytes.length, manifestBytes));
  }

  final encoded = ZipEncoder().encode(arch);
  if (encoded.isEmpty) {
    debugPrint('[Bundle] ERROR: zip encode returned empty');
    return;
  }
  final tmpDir = await getTemporaryDirectory();
  final zipName = _makeFileName(profession, range).replaceAll('.pdf', '.zip');
  final zipPath = p.join(tmpDir.path, zipName);
  final zipFile = File(zipPath)..writeAsBytesSync(encoded, flush: true);
  final zipLen = zipFile.lengthSync();
  debugPrint('[Bundle] wrote: ${zipFile.path} ($zipLen bytes)');

  // 5) Share the ZIP
  debugPrint('[Bundle] sharing zip…');
  await SharePlus.instance.share(
    ShareParams(
      subject: 'CPD records bundle',
      files: [
        XFile(
          zipFile.path,
          mimeType: 'application/zip',
          name: p.basename(zipFile.path),
        ),
      ],
    ),
  );
  debugPrint('[Bundle] share invoked');
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
  return 'cpd_records_$safeProfession${period}_$stamp.pdf';
}

Future<File> _saveTemp(pw.Document doc, String fileName) async {
  final bytes = await doc.save();
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, fileName));
  await f.writeAsBytes(bytes, flush: true);
  return f;
}



bool _isUrl(String s) {
  final ls = s.toLowerCase();
  return ls.startsWith('http://') || ls.startsWith('https://');
}

int? _fileSizeSync(String path) {
  try {
    return File(path).lengthSync();
  } catch (_) {
    return null;
  }
}

String _prettySize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  } else if (bytes >= kb) {
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  } else {
    return '$bytes B';
  }
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

pw.Widget fileRow(String pathOrUrl) {
  if (_isUrl(pathOrUrl)) {
    return pw.UrlLink(
      destination: pathOrUrl,
      child: pw.Text(
        pathOrUrl,
        style: pw.TextStyle(
          color: PdfColors.blue,
          decoration: pw.TextDecoration.underline,
        ),
      ),
    );
  } else {
    final name = p.basename(pathOrUrl);
    final size = _fileSizeSync(pathOrUrl);
    final label = size == null ? name : '$name (${_prettySize(size)})';
    return pw.Text(label);
  }
}

class Att {
  Att({required this.entryTitle, required this.entryDate, required this.pathOrUrl});
  final String entryTitle;
  final DateTime entryDate;
  final String pathOrUrl;
}
