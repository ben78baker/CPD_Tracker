import 'package:cpd_tracker/models.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Shows a bottom sheet for selecting export/share format.
/// Returns the selected choice as a string: 'csv', 'pdf', or 'pdf_bundle'.
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
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('PDF + attachments (bundle)'),
            subtitle: const Text('Records PDF, index PDF and all files'),
            onTap: () {
              debugPrint('Share format picked: PDF_BUNDLE');
              Navigator.pop(ctx, 'pdf_bundle');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}