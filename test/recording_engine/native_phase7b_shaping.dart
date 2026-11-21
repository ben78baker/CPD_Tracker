import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'phase7b_fixtures.dart';
import 'phase7b_html_probe.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Offline PDF shaping probe'))),
    ),
  );
  try {
    final info = await Printing.info();
    // This deprecated bridge remains callable on some platforms that do not
    // advertise it. Its behavior is measured only by this isolated target.
    debugPrintSynchronously('PHASE7B_HTML_ADVERTISED=${info.canConvertHtml}');
    final fonts = {
      for (final name in [
        'Latin-Regular',
        'Latin-Bold',
        'Devanagari-Regular',
        'Devanagari-Bold',
      ])
        name: await rootBundle.load('assets/phase7b_fonts/$name.ttf'),
    };
    final root = await getApplicationDocumentsDirectory();
    final metrics = <Map<String, Object>>[];
    for (final (name, language) in [
      ('hindi', ReportLanguage.hindi),
      ('mixed', ReportLanguage.englishUk),
    ]) {
      final report = await preparedStressReport(
        activities: 3,
        language: language,
        complexScript: true,
      );
      final html = buildShapingProbeHtml(
        report,
        languageTag: language.tag,
        fonts: fonts,
      );
      final timer = Stopwatch()..start();
      final before = ProcessInfo.currentRss;
      final result = await _render(html).timeout(const Duration(seconds: 35));
      final elapsed = timer.elapsedMilliseconds;
      await File('${root.path}/phase7b-$name.pdf').writeAsBytes(result);
      if (result.length < 4000 ||
          String.fromCharCodes(result.take(5)) != '%PDF-') {
        throw StateError('The native bridge did not return a useful PDF.');
      }
      metrics.add({
        'sample': name,
        'bytes': result.length,
        'ms': elapsed,
        'rssBefore': before,
        'rssAfter': ProcessInfo.currentRss,
      });
      debugPrintSynchronously(
        'PHASE7B_HTML_METRICS $name bytes=${result.length} '
        'ms=$elapsed rssBefore=$before rssAfter=${ProcessInfo.currentRss}',
      );
    }
    await File(
      '${root.path}/phase7b-shaping-metrics.json',
    ).writeAsString(jsonEncode(metrics));
    debugPrintSynchronously(
      'PHASE7B_HTML_PASS: Hindi and mixed-language PDFs returned',
    );
  } on Object catch (error, stack) {
    debugPrintSynchronously('PHASE7B_HTML_FAIL: $error\n$stack');
    rethrow;
  }
}

Future<Uint8List> _render(String html) async {
  if (Platform.isIOS) {
    final result = await const MethodChannel(
      'cpd_tracker/phase7b_probe',
    ).invokeMethod<Uint8List>('render', html);
    if (result == null) {
      throw StateError('The isolated iOS bridge returned no bytes.');
    }
    return result;
  }
  // This dependency's deprecated Android bridge is measured only by the probe.
  // ignore: deprecated_member_use
  return Printing.convertHtml(html: html, format: PdfPageFormat.a4);
}
