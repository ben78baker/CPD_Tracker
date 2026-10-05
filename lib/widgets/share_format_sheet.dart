import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Shows a bottom sheet for selecting export/share format.
/// Returns the selected choice as a string: 'csv', 'pdf', 'pdf_evidence', or
/// 'pdf_bundle'.
Future<String?> showShareFormatSheet(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
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
              title: Text(AppLocalizations.of(ctx)!.pdfWithoutEvidence),
              subtitle: Text(
                AppLocalizations.of(ctx)!.pdfWithoutEvidenceSubtitle,
              ),
              onTap: () {
                debugPrint('Share format picked: PDF');
                Navigator.pop(ctx, 'pdf');
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(AppLocalizations.of(ctx)!.pdfWithEvidence),
              subtitle: Text(AppLocalizations.of(ctx)!.pdfWithEvidenceSubtitle),
              onTap: () {
                debugPrint('Share format picked: PDF_EVIDENCE');
                Navigator.pop(ctx, 'pdf_evidence');
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
    ),
  );
}
