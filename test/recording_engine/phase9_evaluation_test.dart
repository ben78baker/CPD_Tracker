import 'package:cpd_tracker/cpd_compatibility/report_locale.dart';
import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/template_evaluation.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase6_creation_pages.dart';
import 'phase6_rehearsal_app.dart';
import 'phase9_evaluation_panel.dart';

const _ledger = TemplateEvaluationLedger();

class _TestRepository implements SqliteRecordingRepository {
  final _rows = <String, Map<String, String>>{};

  @override
  Future<Map<String, String>> loadHostState(String namespace) async =>
      Map.of(_rows[namespace] ?? {});

  @override
  Future<void> saveHostValue(String namespace, String key, String value) async {
    _rows.putIfAbsent(namespace, () => {})[key] = value;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqliteRecordingRepository) run) =>
      run(this);

  @override
  Future<List<RecordingCollection>> loadCollections() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProfessionCreationStore _store(_TestRepository repository) =>
    ProfessionCreationStore(
      repository,
      templates: {(nursingPilot.id, 1): nursingPilot},
      reportRules: {},
      evaluationLedger: _ledger,
    );

Future<void> _consume(_TestRepository repository, int count) =>
    repository.transaction((tx) async {
      for (var i = 0; i < count; i++) {
        await _ledger.accountCreated(
          tx,
          nursingPilot.id,
          'record-$i',
          owned: false,
        );
      }
    });

void main() {
  testWidgets('existing profession catalogue only applies verified purchases', (
    tester,
  ) async {
    final repository = _TestRepository();
    final store = _store(repository);
    await _ledger.initialise(repository);
    final s = lookupAppLocalizations(const Locale('en'));
    Future<void> open() async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => chooseNursingTemplate(
                  context,
                  store,
                  phase7: false,
                  reportLanguage: ReportLanguage.app,
                  existingProfession: true,
                ),
                child: Text(s.p6Templates),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(s.p6Templates));
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.text(s.p6ChooseTemplate), findsNothing);
    expect(find.text(s.evaluationBuy), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await store.acceptSimulatedPurchase(
      'template:${nursingPilot.id}',
      PurchaseState.verified,
    );
    await open();
    expect(find.text(s.p6ChooseTemplate), findsOneWidget);
  });

  test(
    'declared allowance is absent until provisioned and malformed usage cannot grant records',
    () async {
      final repository = _TestRepository();
      final store = _store(repository);
      expect(
        (await store.evaluationStatus(nursingPilot.id)).canCreate,
        isFalse,
      );
      await _ledger.initialise(repository);
      expect((await store.evaluationStatus(nursingPilot.id)).used, 0);
      await repository.saveHostValue(
        TemplateEvaluationLedger.namespace,
        'template:${nursingPilot.id}',
        '["duplicate","duplicate"]',
      );
      expect((await store.evaluationStatus(nursingPilot.id)).used, isNull);
    },
  );

  test(
    'usage reaches the cap across saves and verified purchase takes precedence',
    () async {
      final repository = _TestRepository();
      await _ledger.initialise(repository);
      await _consume(repository, 5);
      final store = _store(repository);
      expect((await store.evaluationStatus(nursingPilot.id)).exhausted, isTrue);
      await expectLater(
        _ledger.accountCreated(
          repository,
          nursingPilot.id,
          'sixth',
          owned: false,
        ),
        throwsA(isA<TemplateAllowanceException>()),
      );
      await store.acceptSimulatedPurchase(
        'template:${nursingPilot.id}',
        PurchaseState.verified,
      );
      expect((await store.evaluationStatus(nursingPilot.id)).owned, isTrue);
    },
  );

  testWidgets(
    'sample preview uses no allowance and checkout shows the same count',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 980));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _TestRepository();
      await _ledger.initialise(repository);
      await _consume(repository, 3);
      final store = _store(repository);
      final s = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        _app(
          ProfessionCreationPage(store: store, first: true, onCreated: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phase6-template')));
      await tester.pumpAndSettle();
      expect(find.text(s.evaluationUsed(3, 5)), findsOneWidget);
      await tester.tap(find.text(s.editorPreview));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(s.editorTry), 140);
      await tester.ensureVisible(find.text(s.editorTry));
      await tester.pumpAndSettle();
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
      await tester.enterText(title, 'Temporary evaluation example');
      expect((await store.evaluationStatus(nursingPilot.id)).used, 3);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(s.evaluationBuy), -100);
      await tester.tap(find.text(s.evaluationBuy));
      await tester.pumpAndSettle();
      expect(find.text(s.evaluationUsed(3, 5)), findsOneWidget);
    },
  );

  testWidgets(
    'exhaustion prevents new saves while keeping the draft and existing records editable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1550));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _TestRepository();
      await _ledger.initialise(repository);
      await _consume(repository, 5);
      final store = _store(repository);
      final layout = LayoutRevision(
        collectionId: 'evaluation-profession',
        version: 1,
        fields: nursingPilot.fields,
        templateId: nursingPilot.id,
        templateVersion: 1,
      );
      final s = lookupAppLocalizations(const Locale('en'));
      final fieldId = layout.fields
          .singleWhere((field) => field.definition.id == 'cpd.title')
          .id;
      final title = find.descendant(
        of: find.byKey(ValueKey(fieldId)),
        matching: find.byType(TextFormField),
      );
      final existing = RecordingRecord(
        id: 'existing',
        collectionId: layout.collectionId,
        layoutVersion: 1,
        version: 1,
        values: {fieldId: 'Saved activity'},
        deleted: false,
      );

      Widget form([RecordingRecord? record]) => _app(
        RehearsalRecordPage(
          key: ValueKey(record?.id),
          store: store,
          collection: layout.collectionId,
          history: [layout],
          record: record,
        ),
      );

      await tester.pumpWidget(form(existing));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(title).enabled, isTrue);
      expect(find.text(s.save), findsOneWidget);
      await tester.pumpWidget(form());
      await tester.pumpAndSettle();
      await tester.enterText(title, 'Pending activity');
      expect(find.text(s.save), findsNothing);
      await tester.tap(find.text(s.evaluationExhausted));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.p6Restore));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.continueLabel));
      await tester.pumpAndSettle();
      expect(find.text('Pending activity'), findsOneWidget);
      expect(find.text(s.save), findsOneWidget);
    },
  );

  testWidgets(
    'evaluation copy and actions fit six locales and eight colours at large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in AppLocalizations.supportedLocales) {
        final s = lookupAppLocalizations(locale);
        for (final accent in AppAccent.values) {
          final repository = _TestRepository();
          await _ledger.initialise(repository);
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
                    TemplateEvaluationPanel(
                      store: _store(repository),
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
          expect(find.text(s.evaluationAvailable(5)), findsOneWidget);
          expect(find.text(s.evaluationTerms(5)), findsOneWidget);
          await tester.ensureVisible(find.text(s.p6ChooseTemplate));
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
