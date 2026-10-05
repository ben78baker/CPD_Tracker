import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/utils/cpd_pdf_document.dart';
import 'package:cpd_tracker/utils/export_attachment.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
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
  }) {
    return prepareCpdPdfPresentation(
      selection: selected,
      dateFormat: dateFormat,
      profile: profile,
      texts: texts,
      attachmentPathResolver: resolveFromTestDocuments,
    );
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
      File(p.join(documentsDirectory.path, storedPhoto))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);

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

    test('builds representative synthetic preview content', () async {
      const availableFile = 'attachments/course-certificate.pdf';
      File(p.join(documentsDirectory.path, availableFile))
        ..createSync(recursive: true)
        ..writeAsStringSync('synthetic evidence');
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
          attachments: ['https://example.com/course-resources', availableFile],
        ),
        entry(
          id: 2,
          date: DateTime(2026, 4, 18),
          title: 'Safeguarding update and reflective practice',
          details: List.filled(
            24,
            'This extended reflection records learning, practical application, '
            'professional discussion, and a planned action for future work.',
          ).join(' '),
          hours: 1,
          minutes: 15,
          attachments: const [
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
        ),
      ]);
      final presentation = await prepare(
        selected,
        profile: const CpdPdfProfile(
          name: 'Alex Morgan',
          company: 'Example Health Ltd',
          address: '10 Example Street\nLondon\nAB1 2CD',
          email: 'alex.morgan@example.com',
        ),
      );
      const previewPath = String.fromEnvironment('CPD_PDF_PREVIEW_PATH');
      final result = previewPath.isEmpty
          ? await render(presentation)
          : await renderCpdPdf(presentation: presentation, texts: texts);
      if (previewPath.isNotEmpty) {
        await File(previewPath).writeAsBytes(result.bytes, flush: true);
      }

      expect(result.pageCount, greaterThanOrEqualTo(1));
      expect(presentation.records, hasLength(3));
    });
  });
}
