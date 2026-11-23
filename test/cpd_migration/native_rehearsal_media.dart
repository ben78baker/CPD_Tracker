import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show getCrc32;
import 'package:cpd_tracker/l10n/app_localizations_de.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/l10n/app_localizations_fr.dart';
import 'package:cpd_tracker/l10n/app_localizations_pt.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/utils/attachment_io.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/utils/pdf_exporter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class RehearsalMedia {
  const RehearsalMedia(this.pdf, this.photo, this.hashes);
  final File pdf;
  final File photo;
  final Map<String, int> hashes;

  static Future<RehearsalMedia> create(Directory docs) async {
    final pdf = await _pdf();
    final png = rehearsalPhoto(16, 0);
    return RehearsalMedia(
      await File(p.join(docs.path, 'CPD-Phase3-Sample.pdf')).writeAsBytes(pdf),
      await File(p.join(docs.path, 'CPD-Phase3-Photo.png')).writeAsBytes(png),
      {'pdf': getCrc32(pdf), 'png': getCrc32(png)},
    );
  }
}

class RehearsalActions extends StatelessWidget {
  const RehearsalActions({super.key, required this.samples});
  final ValueListenable<RehearsalMedia?> samples;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CPD Phase 3A rehearsal')),
    body: Center(
      child: ValueListenableBuilder(
        valueListenable: samples,
        builder: (context, sample, _) {
          if (sample == null) return const Text('Preparing samples');
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () async {
                  try {
                    final box = context.findRenderObject()! as RenderBox;
                    debugPrintSynchronously('CPD_PHASE3_SHARE_OPEN');
                    final result = await SharePlus.instance.share(
                      ShareParams(
                        files: [
                          XFile(sample.pdf.path, mimeType: 'application/pdf'),
                        ],
                        sharePositionOrigin:
                            box.localToGlobal(Offset.zero) & box.size,
                      ),
                    );
                    debugPrintSynchronously(
                      'CPD_PHASE3_SHARE_RESULT ${result.status.name}',
                    );
                  } catch (error) {
                    debugPrintSynchronously(
                      'CPD_PHASE3_SHARE_FAIL ${error.runtimeType}',
                    );
                  }
                },
                child: const Text('Share sample PDF'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final picked = await FilePicker.platform.pickFiles(
                      allowMultiple: false,
                    );
                    final file = picked?.files.single.path;
                    if (file == null) return;
                    final stored = await copyLocalToAppDir(file);
                    final original = await resolveStoredPath(stored);
                    final ext = p
                        .extension(original)
                        .substring(1)
                        .toLowerCase();
                    requireRehearsal(
                      sample.hashes[ext] ==
                          getCrc32(await File(original).readAsBytes()),
                      'Provider changed original bytes',
                    );
                    debugPrintSynchronously('CPD_PHASE3_PICKED_$ext');
                  } catch (error) {
                    debugPrintSynchronously(
                      'CPD_PHASE3_PICK_FAIL ${error.runtimeType}',
                    );
                  }
                },
                child: const Text('Pick sample from files'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> rehearseLocalisedReports(
  Directory temp, {
  bool fetchFonts = true,
}) async {
  CpdPdfFonts? fonts;
  if (fetchFonts) {
    try {
      fonts = await _downloadFonts().timeout(const Duration(seconds: 25));
    } catch (error) {
      debugPrintSynchronously(
        'CPD_PHASE3_FONT_UNAVAILABLE ${error.runtimeType}',
      );
    }
  }
  final docs = await Directory(p.join(temp.path, 'multilingual')).create();
  final media = await RehearsalMedia.create(docs);
  final selection = CpdExportSelection.fromVisibleRecords(
    profession: 'Dentistry',
    range: DateTimeRange(start: DateTime(2024), end: DateTime(2024, 12, 31)),
    visibleRecords: [
      CpdEntry(
        id: 1,
        profession: 'Dentistry',
        date: DateTime(2024, 1, 1),
        title: 'Reflection',
        details: 'Évaluation et révision, prática clínica',
        hours: 1,
        minutes: 5,
        attachments: [media.photo.path, media.pdf.path],
      ),
    ],
  );
  final times = <String, int>{};
  var fontEmbedded = false;
  for (final locale in [
    AppLocalizationsEn(),
    AppLocalizationsDe(),
    AppLocalizationsFr(),
    AppLocalizationsPt(),
  ]) {
    final watch = Stopwatch()..start();
    late CpdPdfPresentation prepared;
    final file = await buildRecordsPdf(
      selection: selection,
      dateFormat: 'dd/MM/yyyy',
      texts: PdfExportTexts.fromLoc(locale),
      evidenceMode: CpdPdfEvidenceMode.embeddedImages,
      fonts: fonts ?? CpdPdfFonts.standard(),
      appIconBytes: rehearsalPhoto(16, 0),
      outputDirectory: docs,
      attachmentPathResolver: (ref) async => ref,
      onPresentationPrepared: (value) => prepared = value,
    );
    final raw = latin1.decode(await file.readAsBytes());
    if (fonts != null && raw.contains('NotoSans')) fontEmbedded = true;
    requireRehearsal(
      prepared.embeddedImageCount == 1 &&
          prepared.documentaryPageCount == 2 &&
          raw.startsWith('%PDF-'),
      'Photo and both source PDF pages render in ${locale.localeName}',
    );
    times[locale.localeName] = watch.elapsedMilliseconds;
  }
  requireRehearsal(
    fonts == null || fontEmbedded,
    'Loaded Noto fonts did not embed',
  );
  debugPrintSynchronously(
    'CPD_PHASE3_NATIVE_REPORT ${jsonEncode({'embeddedNotoFonts': fontEmbedded, 'languageEvidenceTimesMs': times})}',
  );
}

Future<CpdPdfFonts> _downloadFonts() async => CpdPdfFonts(
  regular: await PdfGoogleFonts.notoSansRegular(),
  bold: await PdfGoogleFonts.notoSansBold(),
  italic: await PdfGoogleFonts.notoSansItalic(),
);

Uint8List rehearsalPhoto(int width, int seed) {
  final photo = image.Image(width: width, height: width * 3 ~/ 4);
  var state = seed + 47;
  for (final pixel in photo) {
    state = (state * 1664525 + 1013904223) & 0xffffffff;
    pixel.setRgb(state >> 24, (state >> 16) & 255, (state >> 8) & 255);
  }
  return image.encodePng(photo);
}

Future<Uint8List> _pdf() {
  final source = pw.Document();
  for (final size in [PdfPageFormat.a6, PdfPageFormat.a6.landscape]) {
    source.addPage(
      pw.Page(
        pageFormat: size,
        build: (_) => pw.Text('Synthetic evidence certificate'),
      ),
    );
  }
  return source.save();
}

void requireRehearsal(bool passed, String description) {
  if (!passed) throw StateError(description);
}
