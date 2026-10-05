import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

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
            title: Text(AppLocalizations.of(ctx)!.csvEditable),
            onTap: () {
              debugPrint('Share format picked: CSV');
              Navigator.pop(ctx, 'csv');
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(AppLocalizations.of(ctx)!.pdfReadOnly),
            onTap: () {
              debugPrint('Share format picked: PDF');
              Navigator.pop(ctx, 'pdf');
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(AppLocalizations.of(ctx)!.pdfAttachmentsBundle),
            subtitle: Text(
              AppLocalizations.of(ctx)!.pdfAttachmentsBundleSubtitle,
            ),
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
