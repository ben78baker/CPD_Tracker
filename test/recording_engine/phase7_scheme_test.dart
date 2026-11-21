import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_creation/nursing_bundle.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress.dart';
import 'package:cpd_tracker/cpd_creation/scheme_progress_panel.dart';
import 'package:cpd_tracker/cpd_creation/scheme_report.dart';
import 'package:cpd_tracker/cpd_creation/template_bundle.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:cpd_tracker/widgets/profession_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'phase7_rehearsal_pages.dart' show rehearsalPeriod;

final _bundle = nursingBundle;
final _fields = {for (final field in _bundle.recipe.fields) field.id: field};
String _key(ActivityInput input) => _bundle.inputs[input]!;
final _sample = _bundle.examples.first.values;

Map<String, dynamic> _json() =>
    jsonDecode(_bundle.encode()) as Map<String, dynamic>;
ProfessionTemplateBundle _decode(Map<String, dynamic> payload) =>
    ProfessionTemplateBundle.decode(jsonEncode(payload));

SchemeProgress _progress(
  Iterable<SchemeActivity> activities, {
  SchemePeriod? period,
  ProfessionTemplateBundle? bundle,
  Set<String> evidence = const {'preview.sample'},
}) => calculateSchemeProgress(
  bundle: bundle ?? _bundle,
  period: period ?? rehearsalPeriod,
  activities: activities,
  adoptedFields: _fields,
  availableEvidence: evidence,
);

SchemeActivity _activity(
  String id, [
  Map<String, Object?> updates = const {},
]) => SchemeActivity(
  id,
  _fields.values.toList(),
  {
    ..._sample,
    for (final entry in updates.entries) entry.key: ?entry.value,
  }..removeWhere((id, value) => updates.containsKey(id) && updates[id] == null),
);

void main() {
  setUpAll(initializeDateFormatting);

  test(
    'bundle round-trips deterministically and preserves controlled choice order',
    () {
      final again = ProfessionTemplateBundle.decode(_bundle.encode());
      expect(again.encode(), _bundle.encode());
      final method = again.field(again.inputs[ActivityInput.method]!);
      expect(method.definition.choices.keys, [
        'workshop',
        'study',
        'online',
        'peer',
        'other',
      ]);
      expect(again.recipe.fields, hasLength(11));
      expect(again.protectedKeys.length, 8);
      expect(again.examples, hasLength(3));
    },
  );

  test(
    'invalid bundle reader, rule, references, fields and synthetic data fail closed',
    () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (p) => p['minimumReader'] = 2,
        (p) => p['reviewed'] = '2026-02-29',
        (p) => p['rules']['calculator'] = 'unknown',
        (p) => p['tile']['metrics'] = ['unknown'],
        (p) => p['rules']['inputs']['date'] = 'unknown',
        (p) => p['rules']['inputs']['firstDay'] = _key(ActivityInput.method),
        (p) => p['report']['fields'] = ['unknown'],
        (p) => p['report']['fields'].remove(_key(ActivityInput.method)),
        (p) => p['rules']['metrics'][1]['targetMinutes'] = 2101,
        (p) => p['rules']['metrics'][1]['methods'] = ['unknown'],
        (p) =>
            p['preview']['examples'][0]['values'][_key(
                  ActivityInput.participatory,
                )] =
                121,
        (p) =>
            p['preview']['examples'][0]['values'][_key(
              ActivityInput.evidence,
            )] = [
              'user.file',
            ],
      ];
      for (final mutate in mutations) {
        final payload = _json();
        mutate(payload);
        expect(() => _decode(payload), throwsFormatException);
      }
    },
  );

  test('stable product and explicit revision for a changed threshold', () {
    final payload = _json();
    payload['recipe']['version'] = 2;
    expect(_bundle.changesRegulatoryRules(_decode(payload)), isFalse);
    payload['rules']['metrics'][0]['targetMinutes'] = 2160;
    expect(
      () => _bundle.changesRegulatoryRules(_decode(payload)),
      throwsArgumentError,
    );
    payload['rules']['version'] = 2;
    final offered = _decode(payload);
    expect(_bundle.changesRegulatoryRules(offered), isTrue);
    expect(
      () => _progress([_activity('a')], bundle: offered),
      throwsStateError,
    );
    expect(_progress([_activity('a')]).metrics['total']!.eligible, 120);
    payload['product'] = 'new-product';
    expect(
      () => _bundle.changesRegulatoryRules(_decode(payload)),
      throwsArgumentError,
    );
  });

  test(
    'calendar windows are date-only, end-exclusive and clamp leap anniversaries',
    () {
      final fixed = SchemePeriod.create(
        _bundle,
        id: 'fixed',
        kind: PeriodKind.fixed,
        anchor: '2024-02-29',
      );
      expect(
        (fixed.start, fixed.lastDay, fixed.end),
        ('2024-02-29', '2027-02-27', '2027-02-28'),
      );
      expect(fixed.contains('2024-02-28'), isFalse);
      expect(fixed.contains('2024-02-29'), isTrue);
      expect(fixed.contains('2027-02-28'), isFalse);
      final rolling = SchemePeriod.create(
        _bundle,
        id: 'rolling',
        kind: PeriodKind.rolling,
        anchor: '2026-09-30',
        deadline: '2026-09-01',
      );
      expect(
        (rolling.start, rolling.lastDay, rolling.end),
        ('2023-10-01', '2026-09-30', '2026-10-01'),
      );
      expect(
        SchemePeriod.fromJson(rolling.toJson()).toJson(),
        rolling.toJson(),
      );
      expect(
        () => SchemePeriod.create(
          _bundle,
          id: 'bad',
          kind: PeriodKind.custom,
          anchor: '2026-09-29',
          end: '2026-09-28',
        ),
        throwsArgumentError,
      );
      expect(
        () => SchemePeriod.create(
          _bundle,
          id: 'bad',
          kind: PeriodKind.fixed,
          anchor: '2026-02-29',
        ),
        throwsFormatException,
      );
    },
  );

  test('recorded, complete and category-eligible totals are distinct', () {
    final payload = _json();
    payload['rules']['metrics'][1]['methods'] = ['workshop'];
    final result = _progress([
      _activity('first', {_key(ActivityInput.date): '2024-01-01'}),
      _activity('wrong-category', {_key(ActivityInput.method): 'peer'}),
      _activity('missing-evidence', {
        _key(ActivityInput.evidence): ['missing'],
      }),
      _activity('too-many-minutes', {_key(ActivityInput.participatory): 121}),
      _activity('split', {
        _key(ActivityInput.firstDay): '2023-12-31',
        _key(ActivityInput.date): '2024-01-01',
      }),
      _activity('end-exclusive', {_key(ActivityInput.date): '2027-01-01'}),
      _activity('undated', {_key(ActivityInput.date): 'not a date'}),
      _activity('fractional', {_key(ActivityInput.minutes): 120.5}),
    ], bundle: _decode(payload));
    expect(result.incomplete, 5);
    expect(result.undated, 1);
    expect(result.metrics['total'], (
      recorded: 600,
      complete: 240,
      eligible: 240,
    ));
    expect(result.metrics['participatory'], (
      recorded: 360,
      complete: 180,
      eligible: 90,
    ));
    expect(
      result.activities.map((row) => row.activity.id),
      isNot(contains('end-exclusive')),
    );
    expect(
      result.activities.singleWhere((row) => row.activity.id == 'split').issues,
      contains(ActivityIssue.splitAcrossPeriod),
    );
    expect(
      () => _progress([_activity('duplicate'), _activity('duplicate')]),
      throwsStateError,
    );
  });

  test(
    'replacement fields and changed choices do not inherit original semantics',
    () {
      final method = _fields[_key(ActivityInput.method)]!;
      final choices = Map<String, String>.of(method.definition.choices)
        ..['workshop'] = 'Solo reading';
      final altered = LayoutField(
        id: method.id,
        definition: FieldDefinition.fromJson({
          ...method.definition.toJson(),
          'choices': choices,
        }),
      );
      final removed = _fields[_key(ActivityInput.participatory)]!;
      final replacement = removed.reidentify('another-field');
      final result = _progress([
        SchemeActivity(
          'changed',
          [
            for (final field in _fields.values)
              if (field.id == method.id)
                altered
              else if (field.id == removed.id)
                replacement
              else
                field,
          ],
          {..._sample, replacement.id: 90},
        ),
      ]);
      expect(result.incomplete, 1);
      expect(result.metrics['total']!.eligible, 0);
      expect(result.metrics['participatory']!.recorded, 0);
    },
  );

  test(
    'generated example and multi-page documentation preserve inputs',
    () async {
      final s = AppLocalizationsEn();
      final example = await buildBundleExampleReport(
        bundle: _bundle,
        period: rehearsalPeriod,
        strings: s,
      );
      final paragraphs = List.generate(
        170,
        (n) =>
            'Observation ${n + 1}. A longer fictional discussion about the learning activity.',
      );
      final activity = _activity('long', {
        _key(ActivityInput.details):
            '${paragraphs.join('\n')}\nFINAL OBSERVATION RETAINED',
      });
      final progress = _progress([
        activity,
        _activity('missing', {
          _key(ActivityInput.evidence): ['missing'],
        }),
      ]);
      final long = await buildSchemeReport(
        bundle: _bundle,
        progress: progress,
        bindings: _fields,
        strings: s,
        practitioner: 'Synthetic practitioner',
        evidence: const {
          'preview.sample': (
            name: 'Synthetic certificate',
            available: true,
            url: 'https://example.com/evidence',
          ),
          'missing': (name: 'Missing scan.pdf', available: false, url: null),
        },
      );
      int pages(List<int> data) =>
          RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(data)).length;
      expect(pages(example), greaterThanOrEqualTo(1));
      expect(pages(long), greaterThan(3));
      if (Platform.environment['CPD_PHASE7_ARTIFACTS'] case final dir?) {
        await Directory(dir).create(recursive: true);
        await File('$dir/nmc-example.pdf').writeAsBytes(example);
        await File('$dir/nmc-pagination.pdf').writeAsBytes(long);
        await File(
          '$dir/nmc-bundle.json',
        ).writeAsString('${_bundle.encode()}\n');
      }
    },
  );

  for (final accent in AppAccent.values) {
    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets(
        'card layout at large text · ${accent.name} · ${locale.languageCode}',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 670));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final s = await AppLocalizations.delegate.load(locale);
          var opened = 0;
          Widget card(String name, {Widget? progress}) => ProfessionCard(
            name: name,
            onAdd: () {},
            onScan: () {},
            onView: () {},
            onSearch: () {},
            onRename: () {},
            onDelete: () {},
            target: null,
            refreshToken: 0,
            computeCompleted: (_) async => 0,
            onSetTarget: () => opened++,
            progressContent: progress,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.forAccent(accent),
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.85)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      card(
                        'Long profession name · community and specialist nursing practice',
                        progress: SchemeProgressPanel(
                          bundle: _bundle,
                          progress: _progress([_activity('one')]),
                          onPeriods: () => opened++,
                        ),
                      ),
                      card('Standard CPD'),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
          expect(
            find.text(
              _bundle.label('participatory', 'participatory', s.localeName),
            ),
            findsOneWidget,
          );
          expect(
            find.text(_bundle.label('period', s.p7Period, s.localeName)),
            findsOneWidget,
          );
          expect(find.text(s.setEditTarget), findsOneWidget);
          await tester.ensureVisible(
            find.text(_bundle.label('period', s.p7Period, s.localeName)),
          );
          await tester.tap(
            find.text(_bundle.label('period', s.p7Period, s.localeName)),
          );
          expect(opened, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
