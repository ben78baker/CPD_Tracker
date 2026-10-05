import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/utils/cpd_pdf_document.dart';
import 'package:cpd_tracker/utils/export_attachment.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/utils/pdf_exporter.dart' show buildRecordsBundleZip;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profession = 'Paramedicine';
  final texts = PdfExportTexts.english();
  late Directory documentsDirectory;

  setUp(() {
    documentsDirectory = Directory.systemTemp.createTempSync('cpd_pdf_test_');
  });

  tearDown(() {
    if (documentsDirectory.existsSync()) {
      documentsDirectory.deleteSync(recursive: true);
    }
  });

  CpdEntry entry({
    required int id,
    required DateTime date,
    required String title,
    String details = 'Reflected on learning and application to practice.',
    int hours = 1,
    int minutes = 0,
    List<String> attachments = const [],
  }) {
    return CpdEntry(
      id: id,
      profession: profession,
      date: date,
      title: title,
      details: details,
      hours: hours,
      minutes: minutes,
      attachments: attachments,
    );
  }

  CpdExportSelection selection(
    Iterable<CpdEntry> records, {
    DateTime? start,
    DateTime? end,
  }) {
    return CpdExportSelection.fromVisibleRecords(
      profession: profession,
      range: DateTimeRange(
        start: start ?? DateTime(2026, 1, 1),
        end: end ?? DateTime(2026, 12, 31),
      ),
      visibleRecords: records,
    );
  }

  Future<String> resolveFromTestDocuments(String stored) async {
    if (p.isAbsolute(stored)) return stored;
    return p.join(documentsDirectory.path, stored);
  }

  Future<CpdPdfPresentation> prepare(
    CpdExportSelection selected, {
    String dateFormat = 'dd/MM/yyyy',
    CpdPdfProfile profile = const CpdPdfProfile(),
    CpdPdfEvidenceMode evidenceMode = CpdPdfEvidenceMode.textOnly,
  }) {
    return prepareCpdPdfPresentation(
      selection: selected,
      dateFormat: dateFormat,
      profile: profile,
      texts: texts,
      attachmentPathResolver: resolveFromTestDocuments,
      evidenceMode: evidenceMode,
    );
  }

  File writeBmp(
    String storedPath, {
    required int width,
    required int height,
    int paletteSeed = 0,
  }) {
    final file = File(p.join(documentsDirectory.path, storedPath));
    file.createSync(recursive: true);
    file.writeAsBytesSync(
      _bmpBytes(width, height, paletteSeed: paletteSeed),
      flush: true,
    );
    return file;
  }

  Future<CpdPdfBuildResult> render(CpdPdfPresentation presentation) {
    return renderCpdPdf(
      presentation: presentation,
      texts: texts,
      fonts: CpdPdfFonts.standard(),
      compress: false,
    );
  }

  group('CPD PDF presentation', () {
    test(
      'prepares and renders one ordinary record without attachments',
      () async {
        final presentation = await prepare(
          selection([
            entry(
              id: 1,
              date: DateTime(2026, 2, 14),
              title: 'Clinical assessment workshop',
            ),
          ]),
        );

        final result = await render(presentation);

        expect(presentation.records, hasLength(1));
        expect(presentation.records.single.evidence, isEmpty);
        expect(ascii.decode(result.bytes.take(5).toList()), '%PDF-');
        expect(result.pageCount, 1);
      },
    );

    test(
      'preserves multiple records in deterministic selection order',
      () async {
        final presentation = await prepare(
          selection([
            entry(id: 3, date: DateTime(2026, 4, 3), title: 'Third'),
            entry(id: 1, date: DateTime(2026, 4, 1), title: 'First'),
            entry(id: 2, date: DateTime(2026, 4, 2), title: 'Second'),
          ]),
        );

        expect(presentation.records.map((record) => record.title), [
          'First',
          'Second',
          'Third',
        ]);
        expect((await render(presentation)).bytes, isNotEmpty);
      },
    );

    test('does not truncate a long title', () async {
      final title = List.filled(
        18,
        'Advanced multidisciplinary professional development',
      ).join(' ');
      final presentation = await prepare(
        selection([entry(id: 1, date: DateTime(2026, 3, 1), title: title)]),
      );

      expect(presentation.records.single.title, title);
      expect((await render(presentation)).bytes, isNotEmpty);
    });

    test(
      'allows very long details to span more than two pages with context',
      () async {
        final details = List.generate(
          420,
          (index) =>
              'Reflection ${index + 1}: learning outcome, practical application, '
              'and planned improvement.',
        ).join('\n');
        final presentation = await prepare(
          selection([
            entry(
              id: 1,
              date: DateTime(2026, 5, 1),
              title: 'Extended reflective account',
              details: details,
            ),
          ]),
          profile: const CpdPdfProfile(
            name: 'Alex Morgan',
            company: 'Example Health Ltd',
            email: 'alex@example.com',
          ),
        );

        final result = await render(presentation);

        expect(presentation.records.single.details, details);
        expect(result.pageCount, greaterThan(2));
        expect(
          texts.continuedTitle('Extended reflective account'),
          'Extended reflective account - continued',
        );
        final rawPdf = latin1.decode(result.bytes, allowInvalid: true);
        expect(
          RegExp(r'\[\(continued\)\]TJ').allMatches(rawPdf),
          hasLength(result.pageCount - 1),
        );
        expect(
          RegExp(r'\[\(Alex\)\]TJ').allMatches(rawPdf),
          hasLength(result.pageCount),
        );
        expect(
          RegExp(r'\[\(Paramedicine\)\]TJ').allMatches(rawPdf),
          hasLength(result.pageCount),
        );
        expect(RegExp(r'/XObject<<').allMatches(rawPdf), hasLength(1));
      },
    );

    test('uses the configured date format', () async {
      final presentation = await prepare(
        selection([entry(id: 1, date: DateTime(2026, 7, 4), title: 'Course')]),
        dateFormat: 'MM/dd/yyyy',
      );

      expect(presentation.records.single.date, '07/04/2026');
      expect(presentation.period, '01/01/2026 to 12/31/2026');
    });

    test('formats natural durations and total duration', () async {
      final presentation = await prepare(
        selection([
          entry(
            id: 1,
            date: DateTime(2026, 1, 1),
            title: 'Workshop',
            hours: 2,
            minutes: 30,
          ),
          entry(
            id: 2,
            date: DateTime(2026, 1, 2),
            title: 'Reading',
            hours: 0,
            minutes: 45,
          ),
        ]),
      );

      expect(presentation.records.first.duration, '2 hours 30 minutes');
      expect(presentation.records.last.duration, '45 minutes');
      expect(presentation.totalDuration, '3 hours 15 minutes');
    });

    test('includes populated profile fields and omits empty values', () async {
      final presentation = await prepare(
        selection([entry(id: 1, date: DateTime(2026, 1, 1), title: 'Course')]),
        profile: const CpdPdfProfile(
          name: '  Alex Morgan  ',
          company: 'Example Health Ltd',
          address: '',
          email: 'alex@example.com',
        ),
      );

      expect(presentation.profile.name, 'Alex Morgan');
      expect(presentation.profile.company, 'Example Health Ltd');
      expect(presentation.profile.address, isEmpty);
      expect(presentation.profile.email, 'alex@example.com');
      expect((await render(presentation)).bytes, isNotEmpty);
    });

    test('classifies and renders supported clickable external links', () async {
      const links = [
        'http://example.com/course',
        'https://example.com/evidence',
        'mailto:assessor@example.com',
        'tel:+441234567890',
      ];
      final presentation = await prepare(
        selection([
          entry(
            id: 1,
            date: DateTime(2026, 1, 1),
            title: 'Linked evidence',
            attachments: links,
          ),
        ]),
      );
      final result = await render(presentation);
      final rawPdf = latin1.decode(result.bytes, allowInvalid: true);

      expect(presentation.records.single.evidence.map((item) => item.kind), [
        ExportAttachmentKind.httpUrl,
        ExportAttachmentKind.httpsUrl,
        ExportAttachmentKind.mailtoUrl,
        ExportAttachmentKind.telUrl,
      ]);
      expect(presentation.hyperlinks.map((uri) => uri.toString()), links);
      expect(
        presentation.records.single.evidence.map((item) => item.category),
        ['Web link', 'Web link', 'Email', 'Telephone'],
      );
      expect(presentation.records.single.evidence.map((item) => item.label), [
        'http://example.com/course',
        'https://example.com/evidence',
        'assessor@example.com',
        '+441234567890',
      ]);
      expect(RegExp(r'/URI\s*\(').allMatches(rawPdf), hasLength(4));
    });

    test('lists clean local filenames and reports missing evidence', () async {
      const storedFile = 'attachments/certificate.pdf';
      const storedPhoto = 'attachments/session-photo.jpg';
      const missing = 'attachments/missing-evidence.docx';
      File(p.join(documentsDirectory.path, storedFile))
        ..createSync(recursive: true)
        ..writeAsStringSync('certificate');
      writeBmp(storedPhoto, width: 320, height: 180);

      final presentation = await prepare(
        selection([
          entry(
            id: 1,
            date: DateTime(2026, 1, 1),
            title: 'Evidence review',
            attachments: [storedFile, storedPhoto, missing],
          ),
        ]),
      );
      final evidence = presentation.records.single.evidence;

      expect(evidence[0].label, 'certificate.pdf');
      expect(evidence[0].kind, ExportAttachmentKind.localFile);
      expect(evidence[0].category, 'File');
      expect(evidence[1].label, 'session-photo.jpg');
      expect(evidence[1].kind, ExportAttachmentKind.localImage);
      expect(evidence[1].category, 'Photo');
      expect(evidence[2].label, 'Unavailable: missing-evidence.docx');
      expect(evidence[2].isMissing, isTrue);
      expect(evidence[2].category, 'Unavailable');
      for (final item in evidence) {
        expect(item.label, isNot(contains(documentsDirectory.path)));
        expect(item.label, isNot(contains('attachments/')));
      }
    });

    test(
      'keeps text-only and embedded photographic evidence as distinct modes',
      () async {
        const landscape = 'attachments/landscape-photo.bmp';
        const portrait = 'attachments/portrait-photo.bmp';
        writeBmp(landscape, width: 640, height: 360, paletteSeed: 1);
        writeBmp(portrait, width: 360, height: 640, paletteSeed: 2);
        final selected = selection([
          entry(
            id: 1,
            date: DateTime(2026, 3, 12),
            title: 'Clinical simulation',
            attachments: const [landscape, portrait],
          ),
        ]);

        final withoutEvidence = await prepare(selected);
        final withEvidence = await prepare(
          selected,
          evidenceMode: CpdPdfEvidenceMode.embeddedImages,
        );

        expect(withoutEvidence.evidenceMode, CpdPdfEvidenceMode.textOnly);
        expect(withoutEvidence.embeddedImageCount, 0);
        expect(
          withoutEvidence.records.single.evidence.map((item) => item.label),
          ['landscape-photo.bmp', 'portrait-photo.bmp'],
        );
        expect(
          withoutEvidence.records.single.evidence.every(
            (item) => item.image == null,
          ),
          isTrue,
        );

        expect(withEvidence.evidenceMode, CpdPdfEvidenceMode.embeddedImages);
        expect(withEvidence.embeddedImageCount, 2);
        expect(withEvidence.records.single.evidence.map((item) => item.label), [
          'landscape-photo.bmp',
          'portrait-photo.bmp',
        ]);
        expect(withEvidence.records.single.evidence[0].image!.pixelWidth, 640);
        expect(withEvidence.records.single.evidence[0].image!.pixelHeight, 360);
        expect(withEvidence.records.single.evidence[1].image!.pixelWidth, 360);
        expect(withEvidence.records.single.evidence[1].image!.pixelHeight, 640);

        final withoutResult = await render(withoutEvidence);
        final withResult = await render(withEvidence);
        expect(withoutResult.embeddedImageCount, 0);
        expect(withResult.embeddedImageCount, 2);
        expect(withResult.pageCount, greaterThan(withoutResult.pageCount));
        expect(ascii.decode(withResult.bytes.take(5).toList()), '%PDF-');
      },
    );

    test(
      'keeps multiple photos associated with their source records',
      () async {
        const firstLandscape = 'attachments/first-landscape.bmp';
        const firstPortrait = 'attachments/first-portrait.bmp';
        const secondPhoto = 'attachments/second-photo.bmp';
        writeBmp(firstLandscape, width: 500, height: 280, paletteSeed: 3);
        writeBmp(firstPortrait, width: 280, height: 500, paletteSeed: 4);
        writeBmp(secondPhoto, width: 420, height: 420, paletteSeed: 5);

        final presentation = await prepare(
          selection([
            entry(
              id: 1,
              date: DateTime(2026, 2, 1),
              title: 'First activity',
              attachments: const [firstLandscape, firstPortrait],
            ),
            entry(
              id: 2,
              date: DateTime(2026, 2, 2),
              title: 'Second activity',
              attachments: const [secondPhoto],
            ),
          ]),
          evidenceMode: CpdPdfEvidenceMode.embeddedImages,
        );

        expect(presentation.records.map((record) => record.title), [
          'First activity',
          'Second activity',
        ]);
        expect(presentation.records[0].evidence.map((item) => item.label), [
          'first-landscape.bmp',
          'first-portrait.bmp',
        ]);
        expect(
          presentation.records[1].evidence.single.label,
          'second-photo.bmp',
        );
        expect(presentation.embeddedImageCount, 3);
        final result = await render(presentation);
        expect(result.embeddedImageCount, 3);
        expect(result.pageCount, greaterThanOrEqualTo(4));
      },
    );

    test('embeds a supported PNG at its intrinsic square dimensions', () async {
      const storedPng = 'attachments/app-icon-evidence.png';
      final pngFile = File(p.join(documentsDirectory.path, storedPng));
      pngFile.createSync(recursive: true);
      pngFile.writeAsBytesSync(
        File('assets/icon/1024x1024_app_icon.png').readAsBytesSync(),
        flush: true,
      );

      final presentation = await prepare(
        selection([
          entry(
            id: 1,
            date: DateTime(2026, 4, 2),
            title: 'PNG evidence',
            attachments: const [storedPng],
          ),
        ]),
        evidenceMode: CpdPdfEvidenceMode.embeddedImages,
      );
      final image = presentation.records.single.evidence.single.image!;

      expect(image.pixelWidth, 1024);
      expect(image.pixelHeight, 1024);
      expect((await render(presentation)).embeddedImageCount, 1);
    });

    test(
      'reports corrupt and missing photos without failing either PDF mode',
      () async {
        const corrupt = 'attachments/corrupt-photo.jpg';
        const missing = 'attachments/missing-photo.jpg';
        File(p.join(documentsDirectory.path, corrupt))
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2, 3, 4, 5]);
        final selected = selection([
          entry(
            id: 1,
            date: DateTime(2026, 5, 1),
            title: 'Evidence exceptions',
            attachments: const [corrupt, missing],
          ),
        ]);

        for (final mode in CpdPdfEvidenceMode.values) {
          final presentation = await prepare(selected, evidenceMode: mode);
          final evidence = presentation.records.single.evidence;
          expect(evidence[0].label, 'Unsupported image: corrupt-photo.jpg');
          expect(evidence[0].isUnavailable, isTrue);
          expect(evidence[0].image, isNull);
          expect(evidence[1].label, 'Unavailable: missing-photo.jpg');
          expect(evidence[1].isMissing, isTrue);
          expect(evidence[1].image, isNull);
          expect((await render(presentation)).bytes, isNotEmpty);
        }
      },
    );

    test('cannot reintroduce records outside the Stage 1 selection', () async {
      final selected = selection(
        [
          entry(id: 1, date: DateTime(2025, 12, 31), title: 'Before'),
          entry(id: 2, date: DateTime(2026, 6, 1), title: 'Included'),
          entry(id: 3, date: DateTime(2027, 1, 1), title: 'After'),
        ],
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 12, 31),
      );

      final presentation = await prepare(selected);

      expect(presentation.records.map((record) => record.sourceId), [2]);
      expect(presentation.records.single.title, 'Included');
    });

    test(
      'provides a Page X of Y footer label for every generated page',
      () async {
        final details = List.generate(
          180,
          (index) => 'Detailed reflection line ${index + 1}.',
        ).join('\n');
        final result = await render(
          await prepare(
            selection([
              entry(
                id: 1,
                date: DateTime(2026, 1, 1),
                title: 'Multi-page record',
                details: details,
              ),
            ]),
          ),
        );

        expect(result.pageCount, greaterThan(1));
        expect(result.pageLabels, hasLength(result.pageCount));
        expect(result.pageLabels.first, 'Page 1 of ${result.pageCount}');
        expect(
          result.pageLabels.last,
          'Page ${result.pageCount} of ${result.pageCount}',
        );
      },
    );

    test(
      'preserves long notes, continuation context, headers and photo pages',
      () async {
        const photo = 'attachments/reflective-evidence.bmp';
        writeBmp(photo, width: 720, height: 480, paletteSeed: 6);
        final details = List.generate(
          240,
          (index) =>
              'Reflection ${index + 1}: learning, application and next steps.',
        ).join('\n');
        final presentation = await prepare(
          selection([
            entry(
              id: 1,
              date: DateTime(2026, 8, 10),
              title: 'Extended reflection with evidence',
              details: details,
              attachments: const [photo],
            ),
          ]),
          profile: const CpdPdfProfile(name: 'Alex Morgan'),
          evidenceMode: CpdPdfEvidenceMode.embeddedImages,
        );

        final result = await render(presentation);
        final rawPdf = latin1.decode(result.bytes, allowInvalid: true);
        expect(presentation.records.single.details, details);
        expect(result.pageCount, greaterThan(2));
        expect(result.embeddedImageCount, 1);
        expect(result.pageLabels, hasLength(result.pageCount));
        expect(rawPdf, contains('reflective-evidence'));
        expect(RegExp(r'\[\(Alex\)\]TJ').allMatches(rawPdf), isNotEmpty);
        expect(
          RegExp(r'\[\(Paramedicine\)\]TJ').allMatches(rawPdf),
          isNotEmpty,
        );
      },
    );

    test(
      'ZIP keeps the text-only PDF and byte-identical original evidence',
      () async {
        final originalPhoto = _bmpBytes(480, 300, paletteSeed: 7);
        final photoFile = File(
          p.join(documentsDirectory.path, 'attachments/original-photo.bmp'),
        )..createSync(recursive: true);
        photoFile.writeAsBytesSync(originalPhoto, flush: true);
        final certificateBytes = utf8.encode('original certificate bytes');
        final certificateFile = File(
          p.join(documentsDirectory.path, 'attachments/certificate.pdf'),
        )..createSync(recursive: true);
        certificateFile.writeAsBytesSync(certificateBytes, flush: true);

        final zipFile = await buildRecordsBundleZip(
          selection: selection([
            entry(
              id: 1,
              date: DateTime(2026, 9, 2),
              title: 'Bundle evidence',
              attachments: [photoFile.path, certificateFile.path],
            ),
          ]),
          dateFormat: 'dd/MM/yyyy',
          texts: texts,
          fonts: CpdPdfFonts.standard(),
          appIconBytes: _bmpBytes(48, 48),
          outputDirectory: documentsDirectory,
          attachmentPathResolver: resolveFromTestDocuments,
        );

        final archive = ZipDecoder().decodeBytes(zipFile.readAsBytesSync());
        final names = archive.files.map((file) => file.name).toList();
        expect(names.where((name) => name.endsWith('.pdf')), hasLength(2));
        final archivedPhoto = archive.files.singleWhere(
          (file) => file.name.endsWith('/original-photo.bmp'),
        );
        final archivedCertificate = archive.files.singleWhere(
          (file) => file.name.endsWith('/certificate.pdf'),
        );
        expect(archivedPhoto.readBytes(), originalPhoto);
        expect(archivedCertificate.readBytes(), certificateBytes);

        final summary = archive.files.singleWhere(
          (file) => file.name.startsWith('cpd_records_'),
        );
        final summaryPdf = latin1.decode(
          summary.readBytes()!,
          allowInvalid: true,
        );
        expect(RegExp(r'/Type/Page\b').allMatches(summaryPdf), hasLength(1));
      },
    );

    test('builds both representative Stage 3 preview modes', () async {
      const availableFile = 'attachments/course-certificate.pdf';
      const landscapePhoto = 'attachments/simulation-landscape.bmp';
      const portraitPhoto = 'attachments/reflection-portrait.bmp';
      File(p.join(documentsDirectory.path, availableFile))
        ..createSync(recursive: true)
        ..writeAsStringSync('synthetic evidence');
      writeBmp(landscapePhoto, width: 960, height: 600, paletteSeed: 8);
      writeBmp(portraitPhoto, width: 600, height: 960, paletteSeed: 9);
      final selected = selection([
        entry(
          id: 1,
          date: DateTime(2026, 2, 12),
          title: 'Advanced clinical decision-making workshop',
          details:
              'Reviewed structured assessment techniques and reflected on '
              'how they will improve escalation and documentation in practice.',
          hours: 2,
          minutes: 30,
          attachments: [
            landscapePhoto,
            'http://example.com/course-overview',
            'https://example.com/course-resources',
            availableFile,
          ],
        ),
        entry(
          id: 2,
          date: DateTime(2026, 4, 18),
          title: 'Safeguarding update and reflective practice',
          details: List.generate(
            150,
            (index) =>
                'Reflective point ${index + 1}: this records learning, practical '
                'application, professional discussion, and a planned action.',
          ).join('\n'),
          hours: 1,
          minutes: 15,
          attachments: const [
            portraitPhoto,
            'mailto:learning@example.com',
            'attachments/unavailable-assessment.docx',
          ],
        ),
        entry(
          id: 3,
          date: DateTime(2026, 6, 3),
          title: 'Peer learning meeting',
          details: 'Discussed recent evidence and agreed follow-up actions.',
          hours: 0,
          minutes: 45,
          attachments: const ['tel:+441234567890'],
        ),
      ]);
      const profile = CpdPdfProfile(
        name: 'Alex Morgan',
        company: 'Example Health Ltd',
        address: '10 Example Street\nLondon\nAB1 2CD',
        email: 'alex.morgan@example.com',
      );
      final withoutEvidence = await prepare(selected, profile: profile);
      final withEvidence = await prepare(
        selected,
        profile: profile,
        evidenceMode: CpdPdfEvidenceMode.embeddedImages,
      );
      const withoutPreviewPath = String.fromEnvironment(
        'CPD_PDF_WITHOUT_EVIDENCE_PREVIEW_PATH',
      );
      const withPreviewPath = String.fromEnvironment(
        'CPD_PDF_WITH_EVIDENCE_PREVIEW_PATH',
      );
      final isWritingPreviews =
          withoutPreviewPath.isNotEmpty || withPreviewPath.isNotEmpty;
      final withoutResult = isWritingPreviews
          ? await renderCpdPdf(
              presentation: withoutEvidence,
              texts: texts,
              fonts: CpdPdfFonts.standard(),
            )
          : await render(withoutEvidence);
      final withResult = isWritingPreviews
          ? await renderCpdPdf(
              presentation: withEvidence,
              texts: texts,
              fonts: CpdPdfFonts.standard(),
            )
          : await render(withEvidence);
      if (withoutPreviewPath.isNotEmpty) {
        await File(withoutPreviewPath).parent.create(recursive: true);
        await File(
          withoutPreviewPath,
        ).writeAsBytes(withoutResult.bytes, flush: true);
      }
      if (withPreviewPath.isNotEmpty) {
        await File(withPreviewPath).parent.create(recursive: true);
        await File(withPreviewPath).writeAsBytes(withResult.bytes, flush: true);
      }

      expect(withoutResult.pageCount, greaterThan(1));
      expect(withoutResult.embeddedImageCount, 0);
      expect(withResult.pageCount, greaterThan(withoutResult.pageCount));
      expect(withResult.embeddedImageCount, 2);
      expect(withoutEvidence.records, hasLength(3));
      expect(withEvidence.records, hasLength(3));
      expect(withoutEvidence.hyperlinks, hasLength(4));
      expect(withEvidence.hyperlinks, hasLength(4));
    });
  });
}

Uint8List _bmpBytes(int width, int height, {int paletteSeed = 0}) {
  final rowSize = ((width * 3 + 3) ~/ 4) * 4;
  final pixelDataSize = rowSize * height;
  final bytes = Uint8List(54 + pixelDataSize);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 0x42;
  bytes[1] = 0x4d;
  data.setUint32(2, bytes.length, Endian.little);
  data.setUint32(10, 54, Endian.little);
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, height, Endian.little);
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 24, Endian.little);
  data.setUint32(34, pixelDataSize, Endian.little);

  for (var y = 0; y < height; y++) {
    final sourceY = height - 1 - y;
    final rowStart = 54 + y * rowSize;
    for (var x = 0; x < width; x++) {
      final edge =
          x < 8 || x >= width - 8 || sourceY < 8 || sourceY >= height - 8;
      final offset = rowStart + x * 3;
      bytes[offset] = edge ? 32 : (x * 255 ~/ width + paletteSeed * 17) % 256;
      bytes[offset + 1] = edge
          ? 55
          : (sourceY * 255 ~/ height + paletteSeed * 29) % 256;
      bytes[offset + 2] = edge
          ? 88
          : ((x + sourceY) * 255 ~/ (width + height) + paletteSeed * 41) % 256;
    }
  }
  return bytes;
}
