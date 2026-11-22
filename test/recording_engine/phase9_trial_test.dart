import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/template_trials.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase9_trial_panel.dart';
import 'phase6_creation_pages.dart';
import 'phase6_rehearsal_app.dart';

class _TestTime {
  DateTime wall = DateTime.utc(2026, 3, 27, 12);
  Duration elapsed = Duration.zero;

  TrialClock clock() => TrialClock(utcNow: () => wall, elapsed: () => elapsed);

  void advance(Duration amount) {
    wall = wall.add(amount);
    elapsed += amount;
  }
}

class _TestLedger implements TemplateTrialLedger {
  int observed = 0;
  final started = <String, int>{};

  @override
  Future<TemplateTrialStatus> check(
    String id, {
    required TrialClock clock,
    required bool start,
  }) async {
    final result = evaluateTrial(
      clock: clock,
      previousObservation: observed,
      activation: started[id],
      start: start,
    );
    observed = result.observed;
    if (result.activated case final time?) started[id] = time;
    return result.status;
  }
}

class _Grants implements SqliteRecordingRepository {
  final state = <String, String>{};

  @override
  Future<Map<String, String>> loadHostState(String namespace) async => state;

  @override
  Future<void> saveHostValue(String namespace, String key, String value) async {
    state[key] = value;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqliteRecordingRepository) run) =>
      run(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'preview input does not redeem a trial and catalogue refreshes after explicit start',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 980));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final time = _TestTime();
      final ledger = _TestLedger();
      final store = ProfessionCreationStore(
        _Grants(),
        templates: {(nursingPilot.id, 1): nursingPilot},
        reportRules: {},
        trialLedger: ledger,
        trialClock: time.clock(),
      );
      final s = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        _app(
          ProfessionCreationPage(store: store, onCreated: (_) {}, first: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phase6-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.editorPreview));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(s.editorTry), 140);
      await tester.tap(find.text(s.editorTry));
      await tester.pumpAndSettle();
      final titleId = nursingPilot.fields
          .singleWhere((field) => field.definition.id == 'cpd.title')
          .id;
      final title = find.descendant(
        of: find.byKey(ValueKey(titleId)),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Temporary preview entry');
      expect(ledger.started, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(s.trialStart), -100);
      await tester.tap(find.text(s.trialStart));
      await tester.pumpAndSettle();
      expect(ledger.started.keys, [nursingPilot.id]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(s.trialStart), findsNothing);
      expect(find.text(s.p6ChooseTemplate), findsOneWidget);
    },
  );

  testWidgets(
    'a form open at expiry retains edits and can unlock after restoring purchase',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1550));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final time = _TestTime();
      final ledger = _TestLedger();
      final grants = _Grants();
      final store = ProfessionCreationStore(
        grants,
        templates: {(nursingPilot.id, 1): nursingPilot},
        reportRules: {},
        trialLedger: ledger,
        trialClock: time.clock(),
      );
      final layout = LayoutRevision(
        collectionId: 'trial-profession',
        version: 1,
        fields: nursingPilot.fields,
        templateId: nursingPilot.id,
        templateVersion: 1,
      );
      await store.startTrial(nursingPilot.id);
      final s = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        _app(
          RehearsalRecordPage(
            store: store,
            collection: layout.collectionId,
            history: [layout],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fieldId = layout.fields
          .singleWhere((field) => field.definition.id == 'cpd.title')
          .id;
      final title = find.descendant(
        of: find.byKey(ValueKey(fieldId)),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(title, 'Pending clinical activity');
      expect(find.text(s.save), findsOneWidget);
      time.advance(templateTrialDuration);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Pending clinical activity'), findsOneWidget);
      expect(tester.widget<TextFormField>(title).enabled, isFalse);
      expect(find.text(s.save), findsNothing);
      await tester.tap(find.text(s.trialEnded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.p6Restore));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.continueLabel));
      await tester.pumpAndSettle();
      expect(find.text('Pending clinical activity'), findsOneWidget);
      expect(tester.widget<TextFormField>(title).enabled, isTrue);
      expect(find.text(s.save), findsOneWidget);
    },
  );

  test(
    'UTC expiry is exactly 168 hours, including the local DST change',
    () async {
      final time = _TestTime();
      final clock = time.clock();
      final ledger = _TestLedger();
      Future<TemplateTrialStatus> check({bool start = false}) =>
          ledger.check('route', clock: clock, start: start);
      expect((await check()).state, TemplateTrialState.eligible);
      final redemption = await check(start: true);
      expect(redemption.started, DateTime.utc(2026, 3, 27, 12));
      expect(redemption.expires, DateTime.utc(2026, 4, 3, 12));
      time.advance(templateTrialDuration - const Duration(milliseconds: 1));
      expect((await check()).remaining, const Duration(milliseconds: 1));
      expect((await check(start: true)).started, redemption.started);
      time.advance(const Duration(milliseconds: 1));
      expect((await check(start: true)).state, TemplateTrialState.ended);
    },
  );

  test(
    'process elapsed time advances offline and a backwards restart cannot issue access',
    () async {
      final time = _TestTime();
      final clock = time.clock();
      final ledger = _TestLedger();
      final first = await ledger.check('one', clock: clock, start: true);
      time.elapsed += const Duration(days: 2);
      time.wall = time.wall.subtract(const Duration(days: 1));
      expect(
        (await ledger.check('one', clock: clock, start: true)).remaining,
        const Duration(days: 5),
      );
      final restarted = time.clock();
      expect(
        (await ledger.check('one', clock: restarted, start: true)).state,
        TemplateTrialState.unavailable,
      );
      expect(
        (await ledger.check('two', clock: restarted, start: true)).state,
        TemplateTrialState.unavailable,
      );
      time.wall = first.expires!;
      expect(
        (await ledger.check('one', clock: restarted, start: true)).state,
        TemplateTrialState.ended,
      );
      time.wall = first.started!;
      expect(
        (await ledger.check('one', clock: time.clock(), start: true)).state,
        TemplateTrialState.ended,
      );
      expect(ledger.started.keys, ['one']);
    },
  );

  test('malformed ledger timestamps cannot produce a grant', () {
    expect(
      () => evaluateTrial(
        clock: _TestTime().clock(),
        previousObservation: 0,
        activation: 100,
        start: true,
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'trial activation, three-day and one-day notices, expiry and purchase precedence',
    (tester) async {
      final time = _TestTime();
      final grants = _Grants();
      final ledger = _TestLedger();
      final store = ProfessionCreationStore(
        grants,
        templates: {(nursingPilot.id, 1): nursingPilot},
        reportRules: {},
        trialLedger: ledger,
        trialClock: time.clock(),
      );
      final s = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TemplateTrialPanel(
                store: store,
                templateId: nursingPilot.id,
                onUse: () {},
                purchase: () async =>
                    grants.state['template:${nursingPilot.id}'] = 'verified',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(s.trialTerms), findsOneWidget);
      await tester.tap(find.text(s.trialStart));
      await tester.pumpAndSettle();
      expect(find.text(s.trialStarted), findsOneWidget);
      expect(find.text(s.trialStart), findsNothing);
      time.advance(const Duration(days: 4));
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text(s.trialThreeDays), findsOneWidget);
      time.advance(const Duration(days: 2));
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text(s.trialOneDay), findsOneWidget);
      time.advance(const Duration(days: 1));
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text(s.trialEnded), findsOneWidget);
      await tester.tap(find.text(s.trialEnded));
      await tester.pumpAndSettle();
      expect(find.text(s.trialEnded), findsNothing);
      expect(find.text(s.p6ChooseTemplate), findsOneWidget);
    },
  );

  testWidgets(
    'trial disclosure and action fit all locales and colours on a small screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in AppLocalizations.supportedLocales) {
        final s = lookupAppLocalizations(locale);
        for (final accent in AppAccent.values) {
          final store = ProfessionCreationStore(
            _Grants(),
            templates: {(nursingPilot.id, 1): nursingPilot},
            reportRules: {},
            trialLedger: _TestLedger(),
          );
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey((locale, accent)),
              locale: locale,
              theme: AppTheme.forAccent(accent),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.7)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  children: [
                    TemplateTrialPanel(
                      store: store,
                      templateId: nursingPilot.id,
                      purchase: () async {},
                      onUse: () {},
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(s.trialTerms), findsOneWidget);
          await tester.ensureVisible(find.text(s.trialStart));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);
