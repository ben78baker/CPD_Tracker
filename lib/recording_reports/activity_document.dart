import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'activity_document_data.dart';
import 'continuing_text.dart';

export 'activity_document_data.dart';

/// Detect the script even when the report language differs from user content.
class DevanagariPdfUnsupported implements Exception {
  const DevanagariPdfUnsupported();

  static bool _isDevanagari(int rune) =>
      (rune >= 0x0900 && rune <= 0x097f) ||
      (rune >= 0xa8e0 && rune <= 0xa8ff) ||
      (rune >= 0x11b00 && rune <= 0x11b5f);

  static void check(Iterable<String> text) {
    if (text.any((value) => value.runes.any(_isDevanagari))) {
      throw const DevanagariPdfUnsupported();
    }
  }
}

/// Shared production-style document flow for the current PDF text backend.
Future<Uint8List> buildActivityDocument(
  ActivityDocumentData data, {
  Uint8List? brandIcon,
  pw.Font? regular,
  pw.Font? bold,
  List<pw.Font> fallback = const [],
}) {
  final ActivityDocumentData(
    :title,
    :appName,
    :summaryTitle,
    :metadata,
    :summary,
    :activities,
    :evidenceTitle,
    :evidence,
    :continued,
    :pageOf,
    :summaryColumns,
    :summaryRows,
    :branding,
    :footer,
  ) = data;
  DevanagariPdfUnsupported.check([
    title,
    footer,
    summaryTitle,
    ...metadata,
    ...summary,
    ...summaryColumns,
    ...summaryRows.expand((row) => row),
    evidenceTitle,
    for (final item in evidence) item.label,
    for (final activity in activities) ...[
      activity.title,
      activity.status,
      for (final field in activity.fields) ...[field.label, field.value],
    ],
  ]);
  final document = pw.Document();
  final accent =
      branding == ReportBranding.standard || branding == ReportBranding.subtle
      ? const PdfColor.fromInt(0xff486581)
      : PdfColors.grey900;
  const rule = PdfColors.grey400;
  final heading = pw.TextStyle(
    fontWeight: pw.FontWeight.bold,
    fontSize: 14,
    color: accent,
  );
  final label = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
  const content = pw.TextStyle(
    fontSize: 10,
    lineSpacing: 2,
    color: PdfColors.grey900,
  );
  const small = pw.TextStyle(
    fontSize: 8.5,
    lineSpacing: 2,
    color: PdfColors.grey800,
  );

  pw.Widget text(String value, {pw.TextStyle style = content}) =>
      pw.Text(value, overflow: pw.TextOverflow.span, style: style);

  pw.TableRow row(List<String> cells, {bool header = false}) => pw.TableRow(
    repeat: header,
    decoration: header
        ? const pw.BoxDecoration(color: PdfColors.grey100)
        : null,
    children: [
      for (final (index, cell) in cells.indexed)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            cell,
            style: header || index == 0 || index == cells.length - 1
                ? label
                : content,
          ),
        ),
    ],
  );

  pw.TextSpan referenceSpan(DocumentReference reference) {
    final url = reference.url;
    return pw.TextSpan(
      text: reference.label,
      style: url == null
          ? content
          : content.copyWith(decoration: pw.TextDecoration.underline),
      annotation: url == null ? null : pw.AnnotationUrl(url),
    );
  }

  document.addPage(
    pw.MultiPage(
      maxPages: 1000,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 42, vertical: 38),
      theme: pw.ThemeData.withFont(
        base: regular ?? pw.Font.helvetica(),
        bold: bold ?? pw.Font.helveticaBold(),
        fontFallback: fallback,
      ),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: rule, height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Text(footer, style: small)),
              pw.Text(
                pageOf(context.pageNumber, context.pagesCount),
                style: small,
              ),
            ],
          ),
        ],
      ),
      build: (_) => [
        if (branding == ReportBranding.standard)
          pw.Row(
            children: [
              if (brandIcon != null) ...[
                pw.Image(
                  pw.MemoryImage(brandIcon, dpi: 216),
                  width: 24,
                  height: 24,
                ),
                pw.SizedBox(width: 8),
              ],
              pw.Text(appName, style: label.copyWith(color: accent)),
            ],
          ),
        if (branding == ReportBranding.standard) pw.SizedBox(height: 9),
        text(title, style: heading.copyWith(fontSize: 23)),
        pw.SizedBox(height: 8),
        for (final line in metadata) text(line),
        pw.SizedBox(height: 15),
        pw.Text(summaryTitle, style: heading),
        pw.SizedBox(height: 5),
        if (summaryColumns.isNotEmpty) ...[
          pw.Table(
            columnWidths: const {0: pw.FlexColumnWidth(1.45)},
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: rule, width: 0.35),
            ),
            children: [
              row(summaryColumns, header: true),
              for (final values in summaryRows) row(values),
            ],
          ),
          pw.SizedBox(height: 6),
        ],
        for (final line in summary) text(line, style: small),
        for (final activity in activities) ...[
          pw.NewPage(freeSpace: 65),
          pw.SizedBox(height: 8),
          pw.Divider(color: rule, height: 8),
          ContinuingPdfText(
            continuationLabel: continued(activity.title),
            continuationStyle: label.copyWith(color: accent),
            text: pw.TextSpan(
              style: content,
              children: [
                pw.TextSpan(
                  text: '${activity.title}\n',
                  style: heading.copyWith(fontSize: 13),
                ),
                if (activity.status.isNotEmpty)
                  pw.TextSpan(text: '${activity.status}\n', style: label),
                for (final (index, field) in activity.fields.indexed) ...[
                  pw.TextSpan(text: '${field.label}  ', style: label),
                  pw.TextSpan(text: field.value),
                  if (index + 1 != activity.fields.length)
                    const pw.TextSpan(text: '\n'),
                ],
              ],
            ),
          ),
        ],
        if (evidence.length == 1 && evidence.single.label.length <= 90) ...[
          pw.NewPage(freeSpace: 26),
          pw.SizedBox(height: 7),
          pw.RichText(
            text: pw.TextSpan(
              style: content,
              children: [
                pw.TextSpan(
                  text: '$evidenceTitle  ',
                  style: label.copyWith(color: accent),
                ),
                referenceSpan(evidence.single),
              ],
            ),
            overflow: pw.TextOverflow.span,
          ),
        ] else if (evidence.isNotEmpty) ...[
          pw.NewPage(freeSpace: 43),
          pw.SizedBox(height: 9),
          pw.Text(evidenceTitle, style: heading),
          pw.Divider(color: rule, height: 8),
          for (final reference in evidence)
            pw.RichText(
              text: referenceSpan(reference),
              overflow: pw.TextOverflow.span,
            ),
        ],
      ],
    ),
  );
  return document.save();
}
