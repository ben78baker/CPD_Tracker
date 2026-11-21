import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/l10n/app_localizations_fr.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/template_review.dart';
import 'package:cpd_tracker/recording_reports/activity_document.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/utils/cpd_pdf_document.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/widgets/home_shell.dart';
import 'package:cpd_tracker/widgets/share_format_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;

const _longEnd =
    'Dernière observation. Prüfung abgeschlossen. Revisión terminada.';

void main() {
  test(
    'report locale ignores app language and keeps regional date and number conventions',
    () async {
      final app = AppLocalizationsFr();
      final british = await ReportLocale.resolve(ReportLanguage.englishUk, app);
      final american = await ReportLocale.resolve(
        ReportLanguage.englishUs,
        app,
      );
      final french = await ReportLocale.resolve(
        ReportLanguage.french,
        AppLocalizationsEn(),
      );
      final date = DateTime(2026, 10, 14);
      expect(british.date(date), '14 Oct 2026');
      expect(american.date(date), 'Oct 14, 2026');
      expect(french.date(date), '14 oct. 2026');
      expect(british.duration(90), '1 hour 30 minutes');
      expect(french.duration(90), '1 heure 30 minutes');
      expect(french.duration(74070), '1\u202f234 heures 30 minutes');
      expect(french.decimal('120.0070'), '120,0070');
      expect(app.localeName, 'fr');
    },
  );

  test(
    'independent report preference is persisted and inventoried for legacy recovery',
    () async {
      SharedPreferences.setMockInitialValues({
        'locale_code': 'es',
        'date_format': 'yyyy-MM-dd',
      });
      final settings = SettingsStore.instance;
      expect(await settings.getReportLanguage(), ReportLanguage.app);
      await settings.setReportLanguage(ReportLanguage.french);
      expect(await settings.getReportLanguage(), ReportLanguage.french);
      final inventory = await readCpdLegacyPreferences(
        await SharedPreferences.getInstance(),
      );
      expect(inventory['report_locale_code'], 'fr');
      expect(inventory['locale_code'], 'es');
      expect(inventory['date_format'], 'yyyy-MM-dd');
      await settings.setReportLanguage(ReportLanguage.app);
      expect(await settings.getReportLanguage(), ReportLanguage.app);
    },
  );

  test(
    'Standard PDF honours an explicit report locale and retains legacy defaults',
    () async {
      final date = DateTime(2026, 10, 14);
      final selection = CpdExportSelection.fromVisibleRecords(
        profession: 'Nursing',
        range: DateTimeRange(start: date, end: date),
        visibleRecords: [
          CpdEntry(
            id: 1,
            profession: 'Nursing',
            date: date,
            title: 'Übung en français',
            details: 'Sesión original',
            hours: 1,
            minutes: 30,
            attachments: [],
          ),
        ],
      );
      final locale = await ReportLocale.resolve(
        ReportLanguage.french,
        AppLocalizationsEn(),
      );
      Future<CpdPdfPresentation> project(PdfExportTexts texts) =>
          prepareCpdPdfPresentation(
            selection: selection,
            dateFormat: 'yyyy-MM-dd',
            profile: const CpdPdfProfile(),
            texts: texts,
          );
      final original = await project(
        PdfExportTexts.fromLoc(AppLocalizationsEn()),
      );
      expect(original.records.single.date, '2026-10-14');
      final french = await project(
        PdfExportTexts.fromLoc(locale.strings, reportLocale: locale),
      );
      expect(french.records.single.date, '14 oct. 2026');
      expect(french.records.single.title, 'Übung en français');
      expect(french.records.single.details, 'Sesión original');
    },
  );

  testWidgets('shared Home chrome uses established controls and callbacks', (
    tester,
  ) async {
    String? selection;
    var searches = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeShell(
          onSearch: () => searches++,
          onMenuSelected: (action) => selection = action,
          body: HomeProfessionList(
            itemCount: 1,
            itemBuilder: (_, _) => const Text('Example'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-brand-logo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-search-action')));
    expect(searches, 1);
    await tester.tap(find.byKey(const ValueKey('home-menu-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Profession'));
    await tester.pumpAndSettle();
    expect(selection, 'add_profession');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'report language is optional inside the existing format chooser',
    (tester) async {
      ReportLanguage current = ReportLanguage.app;
      String? format;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  format = await showShareFormatSheet(
                    context,
                    initialLanguage: current,
                    onReportLanguageChanged: (value) => current = value,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();
      expect(current, ReportLanguage.french);
      expect(find.text('Français'), findsOneWidget);
      await tester.tap(find.text(AppLocalizationsEn().pdfWithEvidence));
      await tester.pumpAndSettle();
      expect(format, 'pdf_evidence');
      expect(find.text('Open'), findsOneWidget);
    },
  );

  test(
    'old envelopes decode with subtle brand and reject unknown recipient policy',
    () {
      final original = jsonDecode(nursingBundle.encode()) as Map;
      (original['report'] as Map).remove('branding');
      expect(
        ProfessionTemplateBundle.decode(jsonEncode(original)).branding,
        ReportBranding.subtle,
      );
      original['report']['branding'] = 'publicity';
      expect(
        () => ProfessionTemplateBundle.decode(jsonEncode(original)),
        throwsFormatException,
      );
    },
  );

  test(
    'Devanagari is detected even when recorded text is in a French report',
    () async {
      final french = await ReportLocale.resolve(
        ReportLanguage.french,
        AppLocalizationsEn(),
      );
      expect(
        () => DevanagariPdfUnsupported.check([
          french.strings.p7Summary,
          'Apprentissage et चिकित्सा',
        ]),
        throwsA(isA<DevanagariPdfUnsupported>()),
      );
      final hindi = await ReportLocale.resolve(
        ReportLanguage.hindi,
        AppLocalizationsFr(),
      );
      await expectLater(
        buildBundleExampleReport(
          bundle: nursingBundle,
          period: rehearsalPeriod,
          strings: AppLocalizationsFr(),
          reportLocale: hindi,
        ),
        throwsA(isA<DevanagariPdfUnsupported>()),
      );
    },
  );

  test(
    'the shared layout and codec allow more than 20 fields when the host permits it',
    () {
      final fields = List.generate(
        21,
        (index) => LayoutField(
          id: 'maintenance.$index',
          definition: FieldDefinition(
            id: 'generic.$index',
            version: 1,
            label: 'Inspection item $index',
            kind: FieldKind.text,
          ),
        ),
      );
      final fixture = TemplateVersion(
        id: 'maintenance',
        version: 1,
        label: 'Inspection',
        fields: fields,
      );
      final encoded = encodeTemplateDefinition(fixture);
      expect(decodeTemplateDefinition(encoded).fields, hasLength(21));
      expect(
        () => decodeTemplateDefinition(
          encoded,
          maximumFields: cpdActiveFieldLimit,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'four recipient presentations and long mixed-language PDF content',
    () async {
      final output = Platform.environment['CPD_PHASE7A_ARTIFACTS'];
      final fontPath = Platform.environment['CPD_PHASE7A_FONTS'];
      pw.Font? font(String file) => fontPath == null
          ? null
          : pw.Font.ttf(
              File('$fontPath/$file.ttf').readAsBytesSync().buffer.asByteData(),
            );
      final regular = font('Latin-Regular');
      final bold = font('Latin-Bold');
      final icon = await File(
        'assets/icon/1024x1024_app_icon.png',
      ).readAsBytes();
      const modes = {
        ReportBranding.standard: ReportLanguage.french,
        ReportBranding.subtle: ReportLanguage.englishUk,
        ReportBranding.attribution: ReportLanguage.german,
        ReportBranding.none: ReportLanguage.englishUs,
      };
      for (final item in modes.entries) {
        final payload = jsonDecode(nursingBundle.encode()) as Map;
        payload['report']['branding'] = item.key.name;
        if (item.key == ReportBranding.standard) {
          // A missing translation reproduces a normal catalogue fallback.
          (payload['labels']['nmc.standards'] as Map).remove('fr');
        }
        final bundle = ProfessionTemplateBundle.decode(jsonEncode(payload));
        final locale = await ReportLocale.resolve(
          item.value,
          AppLocalizationsFr(),
        );
        final bytes = await buildBundleExampleReport(
          bundle: bundle,
          period: rehearsalPeriod,
          strings: AppLocalizationsFr(),
          reportLocale: locale,
          brandIcon: icon,
          regular: regular,
          bold: bold,
        );
        expect(_pages(bytes), greaterThanOrEqualTo(1));
        if (output != null) {
          await Directory(output).create(recursive: true);
          await File(
            '$output/${item.key.name}-${item.value.tag}.pdf',
          ).writeAsBytes(bytes);
        }
      }

      final bundle = nursingBundle;
      final locale = await ReportLocale.resolve(
        ReportLanguage.french,
        AppLocalizationsEn(),
      );
      final fields = {
        for (final field in bundle.recipe.fields) field.id: field,
      };
      final first = bundle.examples.first;
      final paragraphs = List.generate(
        170,
        (i) =>
            'Observation ${i + 1}. Apprentissage en français, formación en español und Lernen auf Deutsch.',
      );
      final values = {
        ...first.values,
        bundle.inputs[ActivityInput.details]!:
            '${paragraphs.join('\n')}\n$_longEnd',
      };
      final progress = calculateSchemeProgress(
        bundle: bundle,
        period: rehearsalPeriod,
        activities: [
          SchemeActivity('long', bundle.recipe.fields, values),
          SchemeActivity('missing-evidence', bundle.recipe.fields, {
            ...first.values,
            bundle.inputs[ActivityInput.title]!: 'Follow-up awaiting evidence',
            bundle.inputs[ActivityInput.evidence]!: ['missing'],
          }),
        ],
        adoptedFields: fields,
        availableEvidence: {'preview.sample'},
      );
      final bytes = await buildSchemeReport(
        bundle: bundle,
        progress: progress,
        bindings: fields,
        evidence: const {
          'preview.sample': (
            name: 'Session notes',
            available: true,
            url: 'https://example.com/evidence',
          ),
          'missing': (name: 'Missing scan.pdf', available: false, url: null),
        },
        strings: AppLocalizationsEn(),
        reportLocale: locale,
        practitioner: 'Élodie Silva',
        regular: regular,
        bold: bold,
      );
      expect(_pages(bytes), greaterThan(3));
      if (output != null) {
        await File(
          '$output/multilingual-continuations.pdf',
        ).writeAsBytes(bytes);
      }
    },
  );
}

int _pages(List<int> pdf) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length;
