// lib/utils/csv_exporter.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import 'date_utils.dart';
import '../l10n/app_localizations.dart';

Future<void> exportRecordsCsv({
  required BuildContext context,
  required String profession,
  required String dateFormat,
  required List<CpdEntry> entries,
  required DateTimeRange range,
  String? userName,
  String? company,
  String? email,
}) async {
  final loc = AppLocalizations.of(context)!;
  try {
    // Filter within range
    final filtered = entries.where((e) {
      final d = dateOnly(e.date);
      final s = dateOnly(range.start);
      final t = dateOnly(range.end);
      return (d.isAtSameMomentAs(s) || d.isAfter(s)) &&
          (d.isAtSameMomentAs(t) || d.isBefore(t));
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    // Compute total time
    int totalMinutes = 0;
    for (final e in filtered) {
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

    sb.writeln('"${loc.nameLabel}:","$safeName"');
    sb.writeln('"${loc.companyLabel}:","$safeCompany"');
    sb.writeln('"${loc.emailLabel}:","$safeEmail"');
    sb.writeln(
      '"${loc.professionLabel}:","${profession.replaceAll('"', '""')}"',
    );
    sb.writeln('"${loc.periodLabel}:","$fromStr ${loc.toWord} $toStr"');
    sb.writeln('"${loc.totalTimeLabel}:","${th}h ${tm}m"');
    final withAttachments = filtered
        .where((e) => e.attachments.isNotEmpty)
        .length;
    sb.writeln(
      '"${loc.attachments}:","${withAttachments > 0 ? loc.csvRecordsWithAttachments(withAttachments) : loc.csvNoAttachmentsInExport}"',
    );
    sb.writeln('');
    sb.writeln(
      '${loc.csvDateHeader},${loc.csvTitleHeader},${loc.hoursLabel},${loc.minutesLabel},${loc.detailsLabel},${loc.csvHasAttachmentsHeader}',
    );
    for (final e in filtered) {
      final dateStr = formatDate(e.date, dateFormat).replaceAll(',', ' ');
      final title = e.title.replaceAll('"', '""');
      final details = e.details.replaceAll('\n', ' ').replaceAll('"', '""');
      final has = e.attachments.isNotEmpty ? loc.yes : loc.no;
      sb.writeln(
        '"$dateStr","$title",${e.hours},${e.minutes},"$details","$has"',
      );
    }

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
    await file.writeAsBytes(utf8.encode(sb.toString()), flush: true);

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
        text: loc.cpdEntriesShareText(profession, fromStr, toStr, th, tm),
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
