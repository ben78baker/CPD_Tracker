// lib/utils/csv_exporter.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import 'date_utils.dart';

Future<void> exportRecordsCsv({
  required BuildContext context,
  required String profession,
  required String dateFormat,
  required List<CpdEntry> entries,
  required DateTimeRange range,
}) async {
  try {
    // Filter within range
    final filtered = entries.where((e) {
      final d = dateOnly(e.date);
      final s = dateOnly(range.start);
      final t = dateOnly(range.end);
      return (d.isAtSameMomentAs(s) || d.isAfter(s)) &&
          (d.isAtSameMomentAs(t) || d.isBefore(t));
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

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
    sb.writeln('"Name:",""'); // TODO: populate from settings
    sb.writeln('"Company:",""'); // TODO: populate from settings
    sb.writeln('"Email:",""');
    sb.writeln('"Profession:","${profession.replaceAll('"', '""')}"');
    sb.writeln('"Period:","$fromStr – $toStr"');
    sb.writeln('"Total Time:","${th}h ${tm}m"');
    sb.writeln('');
    sb.writeln('Date,Title,Hours,Minutes,Details,Attachments');
    for (final e in filtered) {
      final dateStr = formatDate(e.date, dateFormat).replaceAll(',', ' ');
      final title = e.title.replaceAll('"', '""');
      final details = e.details.replaceAll('\n', ' ').replaceAll('"', '""');
      final attachments = e.attachments.join('|').replaceAll('"', '""');
      sb.writeln('"$dateStr","$title",${e.hours},${e.minutes},"$details","$attachments"');
    }

    // Write to temp file
    final dir = await getTemporaryDirectory();
    final safeProf = profession.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final ts = DateTime.now();
    final tsStr =
        '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}';
    final path = '${dir.path}/cpd_${safeProf}_$tsStr.csv';
    final file = File(path);
    await file.writeAsBytes(utf8.encode(sb.toString()), flush: true);

    // Share
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'text/csv',
          name: file.uri.pathSegments.last,
        ),
      ],
      text:
          'CPD entries for $profession ($fromStr to $toStr) — Total ${th}h ${tm}m',
    );
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $err')),
      );
    }
  }
}