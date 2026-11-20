// lib/utils/csv_exporter.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import '../l10n/app_localizations.dart';
import 'export_selection.dart';

Future<void> exportRecordsCsv({
  required BuildContext context,
  required CpdExportSelection selection,
  required String dateFormat,
  String? userName,
  String? company,
  String? email,
}) async {
  final loc = AppLocalizations.of(context)!;
  try {
    final profession = selection.profession;

    final document = buildCpdCsv(
      selection: selection,
      dateFormat: dateFormat,
      texts: loc,
      userName: userName,
      company: company,
      email: email,
    );

    // Write to temp file
    final dir = await getTemporaryDirectory();
    final safeProf = profession.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final ts = DateTime.now();
    final tsStr =
        '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}';
    final safePrefix = loc.exportFilePrefix.replaceAll(
      RegExp(r'[^A-Za-z0-9_]'),
      '_',
    );
    final path = '${dir.path}/${safePrefix}_${safeProf}_$tsStr.csv';
    final file = File(path);
    await file.writeAsBytes(utf8.encode(document.text), flush: true);

    // Share using Share Plus instance API
    const origin = Rect.fromLTWH(0, 0, 1, 1);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: 'text/csv',
            name: file.uri.pathSegments.last,
          ),
        ],
        text: loc.cpdEntriesShareText(
          profession,
          document.from,
          document.to,
          document.hours,
          document.minutes,
        ),
        subject: loc.cpdEntriesShareSubject(profession),
        sharePositionOrigin: origin,
      ),
    );
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${loc.exportFailed}: $err')));
    }
  }
}

class CpdCsvDocument {
  const CpdCsvDocument({
    required this.text,
    required this.from,
    required this.to,
    required this.hours,
    required this.minutes,
  });

  final String text;
  final String from;
  final String to;
  final int hours;
  final int minutes;
}

/// The exact CSV payload sent to the share sheet, without filesystem or UI work.
CpdCsvDocument buildCpdCsv({
  required CpdExportSelection selection,
  required String dateFormat,
  required AppLocalizations texts,
  String? userName,
  String? company,
  String? email,
}) {
  final profession = selection.profession;
  final range = selection.range;
  final records = selection.records;
  // Compute total time
  int totalMinutes = 0;
  for (final e in records) {
    totalMinutes += (e.hours * 60) + e.minutes;
  }
  final th = totalMinutes ~/ 60;
  final tm = totalMinutes % 60;

  // Build CSV
  final sb = StringBuffer();
  final fromStr = formatDate(range.start, dateFormat).replaceAll(',', ' ');
  final toStr = formatDate(range.end, dateFormat).replaceAll(',', ' ');
  final safeName = (userName ?? '').replaceAll('"', '""');
  final safeCompany = (company ?? '').replaceAll('"', '""');
  final safeEmail = (email ?? '').replaceAll('"', '""');

  sb.writeln('"${texts.nameLabel}:","$safeName"');
  sb.writeln('"${texts.companyLabel}:","$safeCompany"');
  sb.writeln('"${texts.emailLabel}:","$safeEmail"');
  sb.writeln(
    '"${texts.professionLabel}:","${profession.replaceAll('"', '""')}"',
  );
  sb.writeln('"${texts.periodLabel}:","$fromStr ${texts.toWord} $toStr"');
  sb.writeln('"${texts.totalTimeLabel}:","${th}h ${tm}m"');
  final withAttachments = records.where((e) => e.attachments.isNotEmpty).length;
  sb.writeln(
    '"${texts.attachments}:","${withAttachments > 0 ? texts.csvRecordsWithAttachments(withAttachments) : texts.csvNoAttachmentsInExport}"',
  );
  sb.writeln('');
  sb.writeln(
    '${texts.csvDateHeader},${texts.csvTitleHeader},${texts.hoursLabel},${texts.minutesLabel},${texts.detailsLabel},${texts.csvHasAttachmentsHeader}',
  );
  for (final e in records) {
    final dateStr = formatDate(e.date, dateFormat).replaceAll(',', ' ');
    final title = e.title.replaceAll('"', '""');
    final details = e.details.replaceAll('\n', ' ').replaceAll('"', '""');
    final has = e.attachments.isNotEmpty ? texts.yes : texts.no;
    sb.writeln('"$dateStr","$title",${e.hours},${e.minutes},"$details","$has"');
  }

  return CpdCsvDocument(
    text: sb.toString(),
    from: fromStr,
    to: toStr,
    hours: th,
    minutes: tm,
  );
}
