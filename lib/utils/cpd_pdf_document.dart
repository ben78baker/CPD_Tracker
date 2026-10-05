import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../l10n/app_localizations.dart';
import '../models.dart';
import 'export_attachment.dart';
import 'export_selection.dart';

class PdfExportTexts {
  const PdfExportTexts({
    required this.appTitle,
    required this.allTime,
    required this.to,
    required this.pageOf,
    required this.cpdRecordsTitle,
    required this.nameLabel,
    required this.companyLabel,
    required this.emailLabel,
    required this.professionLabel,
    required this.periodLabel,
    required this.totalTimeLabel,
    required this.dateLabel,
    required this.timeLabel,
    required this.details,
    required this.attachmentsEvidenceLabel,
    required this.noTitle,
    required this.hoursText,
    required this.minutesText,
    required this.fileNotFoundWithName,
    required this.shareSubjectPdf,
    required this.shareSubjectBundle,
    required this.attachmentLinksTitle,
    required this.linksFileName,
    required this.fileNamePrefix,
  });

  factory PdfExportTexts.english() => PdfExportTexts(
    appTitle: 'CPD Progress Tracker',
    allTime: 'All time',
    to: 'to',
    pageOf: (page, total) => 'Page $page of $total',
    cpdRecordsTitle: 'Continuing Professional Development Record',
    nameLabel: 'Name',
    companyLabel: 'Company',
    emailLabel: 'Email',
    professionLabel: 'Profession',
    periodLabel: 'Period',
    totalTimeLabel: 'Total Time',
    dateLabel: 'Date',
    timeLabel: 'Duration',
    details: 'Details / Notes',
    attachmentsEvidenceLabel: 'Evidence / Resources',
    noTitle: '(No title)',
    hoursText: (count) => count == 1 ? '1 hour' : '$count hours',
    minutesText: (count) => count == 1 ? '1 minute' : '$count minutes',
    fileNotFoundWithName: (filename) => 'Unavailable: $filename',
    shareSubjectPdf: 'CPD records',
    shareSubjectBundle: 'CPD records bundle',
    attachmentLinksTitle: 'CPD Attachment Links',
    linksFileName: 'links.txt',
    fileNamePrefix: 'cpd_records',
  );

  factory PdfExportTexts.fromLoc(AppLocalizations loc) => PdfExportTexts(
    appTitle: loc.appTitle,
    allTime: loc.allTime,
    to: loc.toWord,
    pageOf: (page, total) => loc.pageOf(page, total),
    cpdRecordsTitle: loc.cpdPdfDocumentTitle,
    nameLabel: loc.nameLabel,
    companyLabel: loc.companyLabel,
    emailLabel: loc.emailLabel,
    professionLabel: loc.professionLabel,
    periodLabel: loc.periodLabel,
    totalTimeLabel: loc.totalTimeLabel,
    dateLabel: loc.dateLabel,
    timeLabel: loc.cpdPdfDurationLabel,
    details: loc.detailsLabel,
    attachmentsEvidenceLabel: loc.cpdPdfEvidenceResourcesLabel,
    noTitle: loc.noTitle,
    hoursText: loc.hoursPlural,
    minutesText: loc.minutesPlural,
    fileNotFoundWithName: loc.fileNotFoundWithName,
    shareSubjectPdf: loc.cpdRecordsShareSubject,
    shareSubjectBundle: loc.cpdRecordsBundleShareSubject,
    attachmentLinksTitle: loc.attachmentLinksTitle,
    linksFileName: loc.linksFileName,
    fileNamePrefix: loc.exportFilePrefix,
  );

  final String appTitle;
  final String allTime;
  final String to;
  final String Function(int pageNumber, int pagesCount) pageOf;
  final String cpdRecordsTitle;
  final String nameLabel;
  final String companyLabel;
  final String emailLabel;
  final String professionLabel;
  final String periodLabel;
  final String totalTimeLabel;
  final String dateLabel;
  final String timeLabel;
  final String details;
  final String attachmentsEvidenceLabel;
  final String noTitle;
  final String Function(int count) hoursText;
  final String Function(int count) minutesText;
  final String Function(Object filename) fileNotFoundWithName;
  final String shareSubjectPdf;
  final String shareSubjectBundle;
  final String attachmentLinksTitle;
  final String linksFileName;
  final String fileNamePrefix;
}

class CpdPdfProfile {
  const CpdPdfProfile({
    this.name = '',
    this.company = '',
    this.address = '',
    this.email = '',
  });

  final String name;
  final String company;
  final String address;
  final String email;

  CpdPdfProfile normalized() => CpdPdfProfile(
    name: name.trim(),
    company: company.trim(),
    address: address.trim(),
    email: email.trim(),
  );

  bool get isEmpty =>
      name.isEmpty && company.isEmpty && address.isEmpty && email.isEmpty;
}

class CpdPdfEvidence {
  const CpdPdfEvidence({
    required this.kind,
    required this.label,
    this.destination,
  });

  final ExportAttachmentKind kind;
  final String label;
  final Uri? destination;

  bool get isLink => destination != null;
  bool get isMissing => kind == ExportAttachmentKind.missingLocal;
}

class CpdPdfRecord {
  const CpdPdfRecord({
    required this.sourceId,
    required this.date,
    required this.title,
    required this.details,
    required this.duration,
    required this.evidence,
  });

  final int sourceId;
  final String date;
  final String title;
  final String details;
  final String duration;
  final List<CpdPdfEvidence> evidence;
}

/// Complete, privacy-neutral presentation data consumed by the PDF renderer.
///
/// Stored attachment paths are intentionally absent. Local evidence is reduced
/// to a clean filename, while external links retain only their public URI.
class CpdPdfPresentation {
  const CpdPdfPresentation({
    required this.profile,
    required this.profession,
    required this.period,
    required this.totalDuration,
    required this.records,
  });

  final CpdPdfProfile profile;
  final String profession;
  final String period;
  final String totalDuration;
  final List<CpdPdfRecord> records;

  List<Uri> get hyperlinks {
    final links = <Uri>[];
    for (final record in records) {
      for (final evidence in record.evidence) {
        final destination = evidence.destination;
        if (destination != null) links.add(destination);
      }
    }
    return List<Uri>.unmodifiable(links);
  }
}

class CpdPdfFonts {
  const CpdPdfFonts({
    required this.regular,
    required this.bold,
    required this.italic,
  });

  factory CpdPdfFonts.standard() => CpdPdfFonts(
    regular: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    italic: pw.Font.helveticaOblique(),
  );

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
}

class CpdPdfBuildResult {
  const CpdPdfBuildResult({
    required this.bytes,
    required this.pageCount,
    required this.pageLabels,
  });

  final Uint8List bytes;
  final int pageCount;
  final List<String> pageLabels;
}

Future<CpdPdfPresentation> prepareCpdPdfPresentation({
  required CpdExportSelection selection,
  required String dateFormat,
  required CpdPdfProfile profile,
  required PdfExportTexts texts,
  ExportAttachmentPathResolver? attachmentPathResolver,
  ExportAttachmentPathExists? attachmentPathExists,
}) async {
  final records = <CpdPdfRecord>[];
  for (final entry in selection.records) {
    final evidence = <CpdPdfEvidence>[];
    for (final stored in entry.attachments) {
      final attachment = await ExportAttachment.classify(
        stored,
        pathResolver: attachmentPathResolver,
        pathExists: attachmentPathExists,
      );
      evidence.add(_evidencePresentation(attachment, texts));
    }

    records.add(
      CpdPdfRecord(
        sourceId: entry.id,
        date: formatDate(entry.date, dateFormat),
        title: entry.title.trim().isEmpty ? texts.noTitle : entry.title.trim(),
        details: entry.details.trim(),
        duration: _durationText(entry.hours, entry.minutes, texts),
        evidence: List<CpdPdfEvidence>.unmodifiable(evidence),
      ),
    );
  }

  final totalMinutes = selection.records.fold<int>(
    0,
    (total, entry) => total + entry.hours * 60 + entry.minutes,
  );

  return CpdPdfPresentation(
    profile: profile.normalized(),
    profession: selection.profession,
    period:
        '${formatDate(selection.range.start, dateFormat)} '
        '${texts.to} ${formatDate(selection.range.end, dateFormat)}',
    totalDuration: _durationText(totalMinutes ~/ 60, totalMinutes % 60, texts),
    records: List<CpdPdfRecord>.unmodifiable(records),
  );
}

CpdPdfEvidence _evidencePresentation(
  ExportAttachment attachment,
  PdfExportTexts texts,
) {
  switch (attachment.kind) {
    case ExportAttachmentKind.httpUrl:
    case ExportAttachmentKind.httpsUrl:
    case ExportAttachmentKind.mailtoUrl:
    case ExportAttachmentKind.telUrl:
      final value = attachment.uri?.toString() ?? attachment.storedValue.trim();
      return CpdPdfEvidence(
        kind: attachment.kind,
        label: value,
        destination: attachment.uri,
      );
    case ExportAttachmentKind.localImage:
    case ExportAttachmentKind.localFile:
      return CpdPdfEvidence(
        kind: attachment.kind,
        label: _cleanEvidenceName(
          attachment.resolvedPath ?? attachment.storedValue,
        ),
      );
    case ExportAttachmentKind.missingLocal:
      final filename = _cleanEvidenceName(
        attachment.resolvedPath ?? attachment.storedValue,
      );
      return CpdPdfEvidence(
        kind: attachment.kind,
        label: texts.fileNotFoundWithName(filename),
      );
  }
}

String _cleanEvidenceName(String value) {
  final name = p.basename(value.trim());
  return name.isEmpty ? 'Evidence' : name;
}

String _durationText(int hours, int minutes, PdfExportTexts texts) {
  final parts = <String>[];
  if (hours > 0) parts.add(texts.hoursText(hours));
  if (minutes > 0) parts.add(texts.minutesText(minutes));
  if (parts.isEmpty) parts.add(texts.minutesText(0));
  return parts.join(' ');
}

Future<CpdPdfFonts> loadCpdPdfFonts() async {
  try {
    return CpdPdfFonts(
      regular: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
      italic: await PdfGoogleFonts.notoSansItalic(),
    );
  } catch (error) {
    debugPrint(
      '[PDF] Noto Sans was unavailable; using built-in PDF fonts: $error',
    );
    return CpdPdfFonts.standard();
  }
}

Future<CpdPdfBuildResult> renderCpdPdf({
  required CpdPdfPresentation presentation,
  required PdfExportTexts texts,
  CpdPdfFonts? fonts,
  bool compress = true,
}) async {
  final resolvedFonts = fonts ?? await loadCpdPdfFonts();
  final document = pw.Document(
    compress: compress,
    title: texts.cpdRecordsTitle,
    author: presentation.profile.name.isEmpty
        ? null
        : presentation.profile.name,
    creator: texts.appTitle,
    subject: '${presentation.profession} - ${presentation.period}',
    theme: pw.ThemeData.withFont(
      base: resolvedFonts.regular,
      bold: resolvedFonts.bold,
      italic: resolvedFonts.italic,
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(46, 44, 46, 42),
      header: (context) => _buildRepeatingHeader(context, presentation, texts),
      footer: (context) => _buildFooter(context, texts),
      build: (context) => [
        _buildDocumentHeader(presentation, texts),
        pw.SizedBox(height: 24),
        for (final record in presentation.records) ...[
          pw.NewPage(freeSpace: 132),
          _buildRecordHeader(record, texts),
          if (record.details.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _sectionLabel(texts.details),
            pw.SizedBox(height: 4),
            pw.Text(
              record.details,
              overflow: pw.TextOverflow.span,
              style: const pw.TextStyle(
                fontSize: 10.5,
                lineSpacing: 2.2,
                color: _bodyText,
              ),
            ),
          ],
          if (record.evidence.isNotEmpty) ...[
            pw.NewPage(freeSpace: 54),
            pw.SizedBox(height: 12),
            _sectionLabel(texts.attachmentsEvidenceLabel),
            pw.SizedBox(height: 5),
            for (final evidence in record.evidence) _buildEvidenceRow(evidence),
          ],
          pw.SizedBox(height: 15),
          pw.Divider(color: _border, thickness: 0.7),
          pw.SizedBox(height: 12),
        ],
      ],
    ),
  );

  final pageCount = document.document.pdfPageList.pages.length;
  return CpdPdfBuildResult(
    bytes: await document.save(),
    pageCount: pageCount,
    pageLabels: List<String>.generate(
      pageCount,
      (index) => texts.pageOf(index + 1, pageCount),
      growable: false,
    ),
  );
}

const _ink = PdfColor.fromInt(0xff243b53);
const _bodyText = PdfColor.fromInt(0xff334e68);
const _muted = PdfColor.fromInt(0xff627d98);
const _accent = PdfColor.fromInt(0xff486581);
const _surface = PdfColor.fromInt(0xfff4f7fa);
const _border = PdfColor.fromInt(0xffd9e2ec);
const _missing = PdfColor.fromInt(0xff9c4221);
const _link = PdfColor.fromInt(0xff1f5f99);

pw.Widget _buildRepeatingHeader(
  pw.Context context,
  CpdPdfPresentation presentation,
  PdfExportTexts texts,
) {
  if (context.pageNumber == 1) return pw.SizedBox();
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 16),
    padding: const pw.EdgeInsets.only(bottom: 7),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.7)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          texts.appTitle,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.Text(
          presentation.profession,
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ],
    ),
  );
}

pw.Widget _buildFooter(pw.Context context, PdfExportTexts texts) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 12),
    padding: const pw.EdgeInsets.only(top: 7),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _border, width: 0.6)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          texts.appTitle,
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
        pw.Text(
          texts.pageOf(context.pageNumber, context.pagesCount),
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );
}

pw.Widget _buildDocumentHeader(
  CpdPdfPresentation presentation,
  PdfExportTexts texts,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(width: 54, height: 4, color: _accent),
      pw.SizedBox(height: 12),
      pw.Text(
        texts.appTitle,
        style: pw.TextStyle(
          fontSize: 23,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        texts.cpdRecordsTitle,
        style: const pw.TextStyle(fontSize: 11.5, color: _muted),
      ),
      if (!presentation.profile.isEmpty) ...[
        pw.SizedBox(height: 18),
        _buildProfile(presentation.profile),
      ],
      pw.SizedBox(height: 18),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: pw.BoxDecoration(
          color: _surface,
          border: pw.Border.all(color: _border, width: 0.7),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Column(
          children: [
            _summaryRow(texts.professionLabel, presentation.profession),
            pw.SizedBox(height: 6),
            _summaryRow(texts.periodLabel, presentation.period),
            pw.SizedBox(height: 6),
            _summaryRow(texts.totalTimeLabel, presentation.totalDuration),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _buildProfile(CpdPdfProfile profile) {
  final lines = <pw.Widget>[];
  if (profile.name.isNotEmpty) {
    lines.add(
      pw.Text(
        profile.name,
        style: pw.TextStyle(
          fontSize: 11.5,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
    );
  }
  if (profile.company.isNotEmpty) {
    lines.add(
      pw.Text(
        profile.company,
        style: const pw.TextStyle(fontSize: 10, color: _bodyText),
      ),
    );
  }
  if (profile.address.isNotEmpty) {
    lines.add(
      pw.Text(
        profile.address,
        style: const pw.TextStyle(fontSize: 10, color: _bodyText),
      ),
    );
  }
  if (profile.email.isNotEmpty) {
    lines.add(
      pw.UrlLink(
        destination: 'mailto:${profile.email}',
        child: pw.Text(
          profile.email,
          style: const pw.TextStyle(
            fontSize: 10,
            color: _link,
            decoration: pw.TextDecoration.underline,
          ),
        ),
      ),
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: lines,
  );
}

pw.Widget _summaryRow(String label, String value) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 86,
        child: pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: _muted,
            letterSpacing: 0.4,
          ),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ),
    ],
  );
}

pw.Widget _buildRecordHeader(CpdPdfRecord record, PdfExportTexts texts) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: pw.BoxDecoration(
      color: _surface,
      border: pw.Border.all(color: _border, width: 0.7),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${texts.dateLabel.toUpperCase()}  ${record.date}',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _accent,
                letterSpacing: 0.35,
              ),
            ),
            pw.Text(
              '${texts.timeLabel}: ${record.duration}',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Text(
          record.title,
          overflow: pw.TextOverflow.span,
          style: pw.TextStyle(
            fontSize: 14,
            lineSpacing: 1.5,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _sectionLabel(String label) {
  return pw.Text(
    label.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: _accent,
      letterSpacing: 0.45,
    ),
  );
}

pw.Widget _buildEvidenceRow(CpdPdfEvidence evidence) {
  final display = '- ${_wrapLongText(evidence.label)}';
  final text = pw.Text(
    display,
    overflow: pw.TextOverflow.span,
    style: pw.TextStyle(
      fontSize: 9.5,
      lineSpacing: 1.5,
      color: evidence.isMissing ? _missing : _bodyText,
      decoration: evidence.isLink ? pw.TextDecoration.underline : null,
    ),
  );

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 5),
    child: evidence.destination == null
        ? text
        : pw.UrlLink(destination: evidence.destination.toString(), child: text),
  );
}

String _wrapLongText(String value, {int maxSegmentLength = 72}) {
  final output = StringBuffer();
  var segmentLength = 0;
  for (final rune in value.runes) {
    if (segmentLength >= maxSegmentLength) {
      output.write('\n');
      segmentLength = 0;
    }
    output.writeCharCode(rune);
    segmentLength++;
    if ('/?&#='.runes.contains(rune) && segmentLength >= 28) {
      output.write('\n');
      segmentLength = 0;
    }
  }
  return output.toString();
}
