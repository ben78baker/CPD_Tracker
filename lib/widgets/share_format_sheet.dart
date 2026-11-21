import 'package:flutter/material.dart';
import '../cpd_compatibility/report_locale.dart';
import '../l10n/app_localizations.dart';
import 'report_language_tile.dart';
import 'tactile_button.dart';

/// Shows a bottom sheet for selecting export/share format.
/// Returns the selected choice as a string: 'csv', 'pdf', 'pdf_evidence', or
/// 'pdf_bundle'.
Future<String?> showShareFormatSheet(
  BuildContext context, {
  ReportLanguage initialLanguage = ReportLanguage.app,
  ValueChanged<ReportLanguage>? onReportLanguageChanged,
}) async {
  var reportLanguage = initialLanguage;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (context, refresh) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReportLanguageChanged != null)
                ReportLanguageTile(
                  language: reportLanguage,
                  onChanged: (language) {
                    refresh(() => reportLanguage = language);
                    onReportLanguageChanged(language);
                  },
                ),
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
                subtitle: Text(
                  AppLocalizations.of(ctx)!.pdfWithEvidenceSubtitle,
                ),
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
    ),
  );
}

Future<void> showPdfEvidenceOriginalsNotice(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(loc.pdfEvidenceOriginalsNoticeTitle),
      content: Text(loc.pdfEvidenceOriginalsNoticeBody),
      actions: [
        TactileButton(
          onPressed: () => Navigator.pop(ctx),
          variant: TactileButtonVariant.primary,
          child: Text(loc.continueLabel),
        ),
      ],
    ),
  );
}
