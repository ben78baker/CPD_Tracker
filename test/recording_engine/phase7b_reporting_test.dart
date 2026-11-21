import 'dart:typed_data';

import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/recording_reports/activity_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;
import 'phase7b_fixtures.dart';
import 'phase7b_html_probe.dart';

void main() {
  test(
    'recipient document excludes internal metadata kept in app traceability',
    () async {
      final data = await preparedStressReport(activities: 3);
      final details = schemeTraceabilityDetails(
        nursingBundle,
        rehearsalPeriod,
        AppLocalizationsEn(),
      );
      expect(details, [
        'Template version 1',
        'Reporting rules 1',
        'Regulatory review · 21 Nov 2026',
      ]);
      final recipient = [
        data.title,
        data.footer,
        ...data.metadata,
        ...data.summary,
      ].join(' ');
      for (final label in [
        'Template version',
        'Reporting rules',
        'Regulatory review',
        '21 Nov 2026',
      ]) {
        expect(recipient, isNot(contains(label)));
      }
      expect(data.branding, ReportBranding.subtle);
    },
  );

  test(
    'shared, same-name and unavailable evidence maintain distinct references',
    () async {
      final data = await preparedStressReport(activities: 4);
      final historic = data.activities.last;
      expect(
        historic.fields.map((f) => f.value),
        contains('Preserved historical supervisor value'),
      );
      expect(
        data.activities.expand((a) => a.fields).map((f) => f.value),
        isNot(contains('EXCLUDED TEST VALUE')),
      );
      expect(
        data.activities.expand((a) => a.fields).map((f) => f.label),
        isNot(contains('Learning applied to practice')),
      );
      expect(data.evidence, hasLength(4));
      expect(
        data.evidence.where(
          (ref) => ref.label.contains('Shared attendance log.pdf'),
        ),
        hasLength(2),
      );
      expect(
        data.evidence.where((ref) => ref.url != null).map((ref) => ref.url),
        unorderedEquals([evidenceUri, stressUrl]),
      );
      final shared = data.evidence
          .singleWhere((ref) => ref.url == evidenceUri)
          .label
          .split(' · ')
          .first;
      for (final activity in data.activities) {
        expect(
          activity.fields
              .singleWhere((f) => f.label == 'Evidence')
              .value
              .split(', ')
              .where((value) => value == shared),
          hasLength(1),
        );
      }
      expect(
        data.evidence.where(
          (ref) => ref.label.contains('Evidence unavailable'),
        ),
        hasLength(2),
      );
    },
  );

  test(
    'original scheme terminology can come from a language other than English',
    () async {
      final payload = jsonDecode(nursingBundle.encode()) as Map;
      payload['sourceLanguage'] = 'fr';
      final data = await preparedStressReport(
        activities: 1,
        template: ProfessionTemplateBundle.decode(jsonEncode(payload)),
      );
      expect(
        data.summary.last,
        AppLocalizationsEn().reportTemplateLanguageFallback,
      );
      payload['sourceLanguage'] = 'xx';
      expect(
        () => ProfessionTemplateBundle.decode(jsonEncode(payload)),
        throwsFormatException,
      );
    },
  );

  test(
    'Hindi report duration uses Hindi units without rewriting inherited legacy copy',
    () async {
      final hi = await ReportLocale.resolve(
        ReportLanguage.hindi,
        AppLocalizationsEn(),
      );
      expect(hi.duration(90), '1 घंटा 30 मिनट');
      expect(hi.duration(120), '2 घंटे');
      expect(hi.strings.hoursPlural(2), '2 hours');
    },
  );

  test(
    'Brazilian Portuguese uses regional display without replacing saved language IDs',
    () async {
      final br = await ReportLocale.resolve(
        ReportLanguage.fromStored('pt'),
        AppLocalizationsEn(),
      );
      expect(br.strings.localeName, 'pt');
      expect(br.tag, 'pt_BR');
      expect(br.integer(12345), '12.345');
      expect(br.decimal('1.1250'), '1,1250');
    },
  );

  test(
    'multi-year stress PDF and recipient example generate without oversized pages',
    () async {
      final folder = Platform.environment['CPD_PHASE7B_ARTIFACTS'];
      final fonts = Platform.environment['CPD_PHASE7B_FONTS'];
      pw.Font? font(String file) => fonts == null
          ? null
          : pw.Font.ttf(
              File('$fonts/$file.ttf').readAsBytesSync().buffer.asByteData(),
            );
      final duration = Stopwatch()..start();
      final before = ProcessInfo.currentRss;
      final stress = await buildActivityDocument(
        await preparedStressReport(activities: 360),
        regular: font('Latin-Regular'),
        bold: font('Latin-Bold'),
      );
      final elapsed = duration.elapsedMilliseconds;
      final pages = RegExp(
        r'/Type\s*/Page\b',
      ).allMatches(latin1.decode(stress)).length;
      expect(pages, greaterThan(50));
      expect(pages, lessThan(180));
      final example = await buildBundleExampleReport(
        bundle: nursingBundle,
        period: rehearsalPeriod,
        strings: AppLocalizationsEn(),
        regular: font('Latin-Regular'),
        bold: font('Latin-Bold'),
      );
      if (folder != null) {
        await Directory(folder).create(recursive: true);
        if (fonts != null) {
          final localFonts = {
            for (final file in [
              'Latin-Regular',
              'Latin-Bold',
              'Devanagari-Regular',
              'Devanagari-Bold',
            ])
              file: File(
                '$fonts/$file.ttf',
              ).readAsBytesSync().buffer.asByteData(),
          };
          for (final (name, language) in [
            ('hindi', ReportLanguage.hindi),
            ('mixed', ReportLanguage.englishUk),
          ]) {
            final model = await preparedStressReport(
              activities: 3,
              language: language,
              complexScript: true,
            );
            await File('$folder/$name.html').writeAsString(
              buildShapingProbeHtml(
                model,
                languageTag: language.tag,
                fonts: localFonts,
              ),
            );
          }
        }
        await File('$folder/stress-western.pdf').writeAsBytes(stress);
        await File('$folder/nmc-recipient.pdf').writeAsBytes(example);
        await File('$folder/stress-metrics.json').writeAsString(
          jsonEncode({
            'activities': 360,
            'pages': pages,
            'ms': elapsed,
            'bytes': stress.length,
            'rssBefore': before,
            'rssAfter': ProcessInfo.currentRss,
          }),
        );
      }
    },
  );

  test(
    'short and page-boundary fixtures exercise the same pagination path',
    () async {
      final folder = Platform.environment['CPD_PHASE7B_ARTIFACTS'];
      final results = <Uint8List>[];
      for (final length in [1, 38, 67, 121]) {
        final content = ActivityDocumentData(
          title: 'Page boundary regression',
          appName: 'CPD Progress Tracker',
          attribution: '',
          documentTag: '',
          summaryTitle: 'Summary',
          metadata: const [],
          summary: const ['Boundary start'],
          activities: [
            (
              title: 'Long activity',
              status: '',
              fields: [
                (
                  label: 'Notes',
                  value: List.generate(
                    length,
                    (index) => 'Body paragraph ${index + 1}.',
                  ).join('\n'),
                ),
              ],
            ),
            (
              title: 'Last activity',
              status: '',
              fields: [(label: 'Notes', value: 'Boundary end')],
            ),
          ],
          evidenceTitle: 'Evidence',
          evidence: const [
            (label: 'E1 · Evidence reference', url: evidenceUri),
          ],
          continued: (title) => '$title - continued',
          pageOf: (current, total) => 'Page $current of $total',
        );
        final pdf = await buildActivityDocument(content);
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)),
          isNotEmpty,
        );
        results.add(pdf);
      }
      if (folder != null) {
        await Directory(folder).create(recursive: true);
        for (final (index, report) in results.indexed) {
          await File('$folder/boundary-$index.pdf').writeAsBytes(report);
        }
      }
    },
  );
}
