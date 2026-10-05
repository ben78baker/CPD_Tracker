import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange, Rect;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import 'cpd_pdf_document.dart';
import 'export_attachment.dart';
import 'export_selection.dart';

export 'cpd_pdf_document.dart'
    show
        CpdPdfBuildResult,
        CpdPdfFonts,
        CpdPdfPresentation,
        CpdPdfProfile,
        PdfExportTexts,
        prepareCpdPdfPresentation,
        renderCpdPdf;

/// Builds the professional portrait PDF for the centralized export selection.
Future<File> buildRecordsPdf({
  required CpdExportSelection selection,
  required String dateFormat,
  String? userName,
  String? company,
  String? address,
  String? email,
  PdfExportTexts? texts,
}) async {
  final resolvedTexts = texts ?? PdfExportTexts.english();
  final presentation = await prepareCpdPdfPresentation(
    selection: selection,
    dateFormat: dateFormat,
    profile: CpdPdfProfile(
      name: userName ?? '',
      company: company ?? '',
      address: address ?? '',
      email: email ?? '',
    ),
    texts: resolvedTexts,
  );
  final result = await renderCpdPdf(
    presentation: presentation,
    texts: resolvedTexts,
  );
  return _saveTemp(
    result.bytes,
    _makeFileName(
      resolvedTexts.fileNamePrefix,
      selection.profession,
      selection.range,
    ),
  );
}

/// Builds the PDF and invokes the native share sheet.
Future<void> exportRecordsPdf({
  required CpdExportSelection selection,
  required String dateFormat,
  String? userName,
  String? company,
  String? address,
  String? email,
  PdfExportTexts? texts,
}) async {
  final resolvedTexts = texts ?? PdfExportTexts.english();
  final file = await buildRecordsPdf(
    selection: selection,
    dateFormat: dateFormat,
    userName: userName,
    company: company,
    address: address,
    email: email,
    texts: resolvedTexts,
  );

  try {
    debugPrint('[PDF] path: ${file.path} (${await file.length()} bytes)');
  } catch (_) {}

  const origin = Rect.fromLTWH(0, 0, 1, 1);
  await SharePlus.instance.share(
    ShareParams(
      subject: resolvedTexts.shareSubjectPdf,
      files: [
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: p.basename(file.path),
        ),
      ],
      sharePositionOrigin: origin,
    ),
  );
}

/// Builds a ZIP containing the redesigned summary PDF and the original local
/// evidence files. The existing bundle folder structure is intentionally kept.
Future<void> exportRecordsBundleZip({
  required CpdExportSelection selection,
  required String dateFormat,
  String? userName,
  String? company,
  String? address,
  String? email,
  PdfExportTexts? texts,
}) async {
  final resolvedTexts = texts ?? PdfExportTexts.english();
  final profession = selection.profession;
  final range = selection.range;
  final pdfFile = await buildRecordsPdf(
    selection: selection,
    dateFormat: dateFormat,
    userName: userName,
    company: company,
    address: address,
    email: email,
    texts: resolvedTexts,
  );

  final localsByFolder = <String, List<String>>{};
  final urlsByFolder = <String, List<String>>{};
  var missingCount = 0;
  for (final entry in selection.records) {
    if (entry.attachments.isEmpty) continue;
    final datePart = formatDate(entry.date, 'yyyy-MM-dd');
    final titlePartFull = _safeFileName(entry.title);
    final titlePart = titlePartFull.length > 40
        ? titlePartFull.substring(0, 40)
        : titlePartFull;
    final folder = p.join('attachments', '$datePart - $titlePart');
    for (final stored in entry.attachments) {
      final attachment = await ExportAttachment.classify(stored);
      if (attachment.isUrl) {
        (urlsByFolder[folder] ??= <String>[]).add(stored);
      } else if (attachment.isAvailableLocal) {
        (localsByFolder[folder] ??= <String>[]).add(attachment.resolvedPath!);
      } else {
        missingCount++;
        debugPrint(
          '[Bundle] missing evidence: ${attachment.resolvedPath ?? stored}',
        );
      }
    }
  }

  final localCount = localsByFolder.values.fold<int>(
    0,
    (sum, paths) => sum + paths.length,
  );
  final urlCount = urlsByFolder.values.fold<int>(
    0,
    (sum, urls) => sum + urls.length,
  );
  debugPrint(
    '[Bundle] locals: $localCount, urls: $urlCount, missing: '
    '$missingCount, folders: ${localsByFolder.length + urlsByFolder.length}',
  );

  final archive = Archive();
  archive.addFile(
    ArchiveFile.stream(p.basename(pdfFile.path), InputFileStream(pdfFile.path)),
  );

  for (final entry in localsByFolder.entries) {
    for (final path in entry.value) {
      archive.addFile(
        ArchiveFile.stream(
          p.join(entry.key, p.basename(path)),
          InputFileStream(path),
        ),
      );
    }
  }

  for (final entry in urlsByFolder.entries) {
    final manifest = StringBuffer('${resolvedTexts.attachmentLinksTitle}\n\n');
    manifest.writeln(
      '${resolvedTexts.periodLabel}: '
      '${formatDate(range.start, 'dd/MM/yyyy')} ${resolvedTexts.to} '
      '${formatDate(range.end, 'dd/MM/yyyy')}\n',
    );
    for (final url in entry.value) {
      manifest.writeln(url);
    }
    final bytes = utf8.encode(manifest.toString());
    archive.addFile(
      ArchiveFile(
        '${entry.key}/${resolvedTexts.linksFileName}',
        bytes.length,
        bytes,
      ),
    );
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded.isEmpty) {
    debugPrint('[Bundle] ERROR: zip encode returned empty');
    return;
  }
  final temporaryDirectory = await getTemporaryDirectory();
  final zipName = _makeFileName(
    resolvedTexts.fileNamePrefix,
    profession,
    range,
  ).replaceAll('.pdf', '.zip');
  final zipFile = File(p.join(temporaryDirectory.path, zipName));
  await zipFile.writeAsBytes(encoded, flush: true);
  debugPrint('[Bundle] wrote: ${zipFile.path} (${zipFile.lengthSync()} bytes)');

  const origin = Rect.fromLTWH(0, 0, 1, 1);
  await SharePlus.instance.share(
    ShareParams(
      subject: resolvedTexts.shareSubjectBundle,
      files: [
        XFile(
          zipFile.path,
          mimeType: 'application/zip',
          name: p.basename(zipFile.path),
        ),
      ],
      sharePositionOrigin: origin,
    ),
  );
}

String _safeFileName(String input) {
  final sanitized = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.replaceAll(RegExp(r'\s+'), '_');
}

String _dateToken(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}'
    '${date.month.toString().padLeft(2, '0')}'
    '${date.day.toString().padLeft(2, '0')}';

String _makeFileName(String prefix, String profession, DateTimeRange range) {
  final now = DateTime.now();
  final timestamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}';
  final period = '_${_dateToken(range.start)}-${_dateToken(range.end)}';
  final safePrefix = _safeFileName(
    prefix,
  ).replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  return '${safePrefix}_${_safeFileName(profession)}${period}_$timestamp.pdf';
}

Future<File> _saveTemp(Uint8List bytes, String fileName) async {
  final directory = await getTemporaryDirectory();
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
