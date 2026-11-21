import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

typedef DocumentField = ({String label, String value});
typedef DocumentActivity = ({
  String title,
  String status,
  List<DocumentField> fields,
});
typedef DocumentReference = ({String label, String? url});

/// Shared document flow. The caller supplies printable strings and evidence
/// references. This renderer is independent of an activity's field semantics.
Future<Uint8List> buildActivityDocument({
  required String title,
  required String footer,
  required String summaryTitle,
  required List<String> metadata,
  required List<String> summary,
  required List<DocumentActivity> activities,
  required String evidenceTitle,
  required List<DocumentReference> evidence,
  String? versionNote,
  pw.Font? regular,
  pw.Font? bold,
  List<pw.Font> fallback = const [],
}) {
  final document = pw.Document();
  const rule = PdfColors.grey400;
  final heading = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15);
  final label = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
  pw.Widget text(String value, {double size = 10}) => pw.Text(
    value,
    overflow: pw.TextOverflow.span,
    style: pw.TextStyle(
      fontSize: size,
      lineSpacing: 2,
      color: PdfColors.grey900,
    ),
  );

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
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            footer,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
          ),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
      build: (_) => [
        pw.Text(
          title,
          overflow: pw.TextOverflow.span,
          style: heading.copyWith(fontSize: 24, color: PdfColors.blueGrey900),
        ),
        pw.SizedBox(height: 9),
        for (final line in metadata) text(line),
        pw.SizedBox(height: 16),
        pw.Text(summaryTitle, style: heading),
        pw.Divider(color: rule, height: 12),
        for (final line in summary) ...[text(line), pw.SizedBox(height: 3)],
        if (versionNote != null) ...[
          pw.SizedBox(height: 8),
          text(versionNote, size: 8),
        ],
        for (final activity in activities) ...[
          // Keep the first line of the activity with its title where possible.
          pw.NewPage(freeSpace: 97),
          pw.SizedBox(height: 14),
          pw.Divider(color: rule, height: 11),
          pw.Text(
            activity.title,
            overflow: pw.TextOverflow.span,
            style: heading,
          ),
          if (activity.status.isNotEmpty) text(activity.status, size: 9),
          for (final field in activity.fields) ...[
            pw.NewPage(freeSpace: 38),
            pw.SizedBox(height: 7),
            pw.Text(field.label, overflow: pw.TextOverflow.span, style: label),
            text(field.value),
          ],
        ],
        if (evidence.isNotEmpty) ...[
          pw.NewPage(freeSpace: 75),
          pw.SizedBox(height: 17),
          pw.Text(evidenceTitle, style: heading),
          pw.Divider(color: rule, height: 12),
          for (final reference in evidence)
            if (reference.url case final url?
                when reference.label.length <= 120)
              pw.UrlLink(
                destination: url,
                child: pw.Text(
                  reference.label,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              )
            else
              text(reference.label),
        ],
      ],
    ),
  );
  return document.save();
}
