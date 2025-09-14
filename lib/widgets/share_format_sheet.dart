import 'package:cpd_tracker/models.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a bottom sheet for selecting export/share format.
/// Returns the selected choice as a string: 'csv' or 'pdf'.
Future<String?> showShareFormatSheet(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('CSV (editable)'),
            onTap: () {
              debugPrint('Share format picked: CSV');
              Navigator.pop(ctx, 'csv');
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('PDF (read-only)'),
            onTap: () async {
              debugPrint('Share format picked: PDF');
              Navigator.pop(ctx, 'pdf');
              // Update this call in your calling page to pass real data using named parameters!
              // Example:
              // await exportRecordsPdf(context, profession: ..., entries: [...], ...);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> exportRecordsPdf(
  BuildContext context, {
  required String profession,
  required List<CpdEntry> entries,
  DateTimeRange? range,
  String? userName,
  String? company,
  String? email,
}) async {
  String fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  debugPrint('exportRecordsPdf called for $profession with ${entries.length} entries');
  if (range != null) {
    debugPrint('Filtering range: ${fmtDate(range.start)} – ${fmtDate(range.end)}');
  }

  // Filter by range if provided
  final filtered = range == null
      ? entries
      : entries.where((e) {
          final d = DateTime(e.date.year, e.date.month, e.date.day);
          final s = DateTime(range.start.year, range.start.month, range.start.day);
          final t = DateTime(range.end.year, range.end.month, range.end.day);
          return !d.isBefore(s) && !d.isAfter(t);
        }).toList();

  // Compute total time
  int totalMinutes = 0;
  for (final e in filtered) {
    totalMinutes += (e.hours * 60) + e.minutes;
  }
  final totalH = totalMinutes ~/ 60;
  final totalM = totalMinutes % 60;

  debugPrint('Total time = ${totalH}h ${totalM}m across ${filtered.length} records');

  // Build table data
  final headers = <String>['Date', 'Title', 'Hours', 'Minutes', 'Details', 'Attachments'];
  final data = filtered.map((e) {
    final attachments = (e.attachments ?? const <String>[])
        .map((a) => a.split('/').last)
        .join(' | ');
    return [
      fmtDate(e.date),
      e.title,
      e.hours.toString(),
      e.minutes.toString(),
      e.details,
      attachments,
    ];
  }).toList();

  final pdf = pw.Document();

  // Header block helper
  pw.Widget headerLine(String label, String value) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Expanded(child: pw.Text(value)),
        ],
      );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) {
        return [
          pw.Text('CPD Records', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (userName != null && userName.trim().isNotEmpty) headerLine('Name', userName),
          headerLine('Profession', profession),
          if (company != null && company.trim().isNotEmpty) headerLine('Company', company),
          if (email != null && email.trim().isNotEmpty) headerLine('Email', email),
          if (range != null)
            headerLine('Period', '${fmtDate(range.start)} to ${fmtDate(range.end)}')
          else
            headerLine('Period', 'All records'),
          headerLine('Total Time', '${totalH}h ${totalM}m'),
          pw.SizedBox(height: 12),
          if (data.isEmpty)
            pw.Text('No records in the selected period.')
          else
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2), // date
                1: const pw.FlexColumnWidth(2.0), // title
                2: const pw.FlexColumnWidth(0.8), // hours
                3: const pw.FlexColumnWidth(0.9), // minutes
                4: const pw.FlexColumnWidth(2.5), // details
                5: const pw.FlexColumnWidth(2.0), // attachments
              },
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            ),
        ];
      },
    ),
  );

  final bytes = await pdf.save();
  final filename = 'cpd_records_${DateTime.now().millisecondsSinceEpoch}.pdf';

  debugPrint('Saving PDF file: $filename');

  try {
    // Primary path: use share_plus with a temp file (more reliable on some iOS versions)
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: filename)],
      text: 'CPD records',
      subject: 'CPD records',
    );
  } catch (err, st) {
    debugPrint('Primary PDF share failed: $err');
    debugPrint(st.toString());
    // Fallback to printing plugin share if something goes wrong saving the file
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}