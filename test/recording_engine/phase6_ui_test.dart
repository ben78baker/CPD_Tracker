import 'package:cpd_tracker/cpd_creation/creation_policy.dart';
import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_migration/legacy_migration.dart'
    show cpdStandardFields;
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/onboarding_page.dart';
import 'package:cpd_tracker/recording_editor/edit_fields_page.dart';
import 'package:cpd_tracker/recording_engine/field_library.dart';
import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase6_creation_pages.dart';

Widget _app(
  Widget page, {
  Locale locale = const Locale('en'),
  AppAccent accent = AppAccent.purple,
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  theme: AppTheme.forAccent(accent),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

class _EmptyDrafts implements SqliteRecordingRepository {
  _EmptyDrafts([this.layout]);
  final LayoutRevision? layout;

  @override
  Future<Map<String, String>> loadHostState(String namespace) async => {};
  @override
  Future<List<LayoutRevision>> loadLayouts(String collectionId) async => [
    layout!,
  ];
  @override
  Future<Set<String>> fieldsWithValues(String collectionId) async => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CustomDraftStore extends ProfessionCreationStore {
  _CustomDraftStore(this.baseline)
    : super(_EmptyDrafts(baseline), templates: {}, reportRules: {});

  final LayoutRevision baseline;
  ProfessionDraft? saved;
  String? committed;

  @override
  Future<CreationAccess> access() async => CreationAccess(customFields: true);

  @override
  Future<LayoutRevision> supplied(ProfessionDraft draft) async => baseline;

  @override
  Future<void> persist(ProfessionDraft draft) async => saved = draft;

  @override
  Future<String> commit(
    String requestId, {
    bool firstProfession = false,
    bool acceptIncomplete = false,
  }) async {
    committed = requestId;
    return baseline.collectionId;
  }
}

void main() {
  final locales = [
    ...AppLocalizations.supportedLocales,
    const Locale('en'),
    const Locale('fr'),
  ];
  for (final (index, locale) in locales.indexed) {
    testWidgets(
      'shared choices on small screen: ${locale.languageCode} ${AppAccent.values[index].name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 680);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final store = ProfessionCreationStore(
          _EmptyDrafts(),
          templates: {},
          reportRules: {},
        );
        for (final first in [true, false]) {
          await tester.pumpWidget(
            _app(
              ProfessionCreationPage(
                store: store,
                first: first,
                onCreated: (_) {},
              ),
              accent: AppAccent.values[index],
              locale: locale,
              scale: 1.7,
            ),
          );
          await tester.pumpAndSettle();
          for (final kind in ['standard', 'custom', 'template']) {
            final choice = find.byKey(ValueKey('phase6-$kind'));
            await tester.scrollUntilVisible(choice, 100);
            expect(choice, findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  for (final editing in [false, true]) {
    testWidgets(
      'Custom CPD can create a field and configure reports when ${editing ? 'editing' : 'setting up'}',
      (tester) async {
        tester.view.physicalSize = const Size(400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final baseline = LayoutRevision(
          collectionId: 'custom-cpd',
          version: 1,
          fields: cpdStandardFields('custom-cpd'),
        );
        final store = _CustomDraftStore(baseline);
        final draft = ProfessionDraft(
          id: 'draft',
          kind: ProfessionKind.custom,
          name: 'Engineering',
          layout: LayoutDraft(baseline, maxActiveFields: 20),
          report: ReportSelection(),
          editing: editing ? baseline.collectionId : null,
        );
        final page = ProfessionDraftPage(store: store, draft: draft);
        String? result;
        await tester.pumpWidget(
          _app(
            editing
                ? Scaffold(
                    body: Builder(
                      builder: (context) => PopupMenuButton<String>(
                        onSelected: (_) async {
                          result = await Navigator.of(context).push(
                            MaterialPageRoute<String>(builder: (_) => page),
                          );
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit fields'),
                          ),
                        ],
                      ),
                    ),
                  )
                : page,
          ),
        );
        await tester.pumpAndSettle();
        if (editing) {
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit fields'));
          await tester.pumpAndSettle();
          expect(find.byType(EditFieldsPage), findsOneWidget);
          expect(
            find.widgetWithText(OutlinedButton, 'Edit fields'),
            findsNothing,
          );
        } else {
          await tester.tap(find.widgetWithText(OutlinedButton, 'Edit fields'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('open-add-field')));
        await tester.pumpAndSettle();
        expect(find.text('Field Library'), findsOneWidget);
        await tester.tap(find.text('Create custom field'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Short text'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Field name'),
          'Project code',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add field'));
        await tester.pumpAndSettle();
        expect(find.text('6 of 20 fields'), findsOneWidget);
        final menu = find.byTooltip('Menu: Project code');
        await tester.scrollUntilVisible(
          menu,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ReorderableListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from reports'));
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Include in reports'), findsOneWidget);
        await tester.tap(find.text('Include in reports'));
        await tester.pumpAndSettle();
        expect(store.saved!.report.excluded, isEmpty);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from reports'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        final field = store.saved!.layout.fields.last;
        expect(field.definition.kind, FieldKind.text);
        expect(field.label, 'Project code');
        expect(store.saved!.report.excluded, contains(field.id));
        expect(store.committed, editing ? draft.id : isNull);
        expect(result, editing ? baseline.collectionId : isNull);
      },
    );
  }

  testWidgets(
    'Welcome has no profession name and saves its preferences before Continue',
    (tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final written = <String, String>{};
      bool continued = false;
      final locale = ValueNotifier<Locale?>(const Locale('en'));
      final accent = ValueNotifier(AppAccent.teal);
      addTearDown(locale.dispose);
      addTearDown(accent.dispose);
      final preferences = OnboardingPreferences(
        locale: locale,
        accent: accent,
        initial: {'week': 'monday', 'name': 'Test User'},
        save: (key, value) async {
          written[key] = value;
        },
        onContinue: () {
          continued = true;
        },
      );
      await tester.pumpWidget(_app(OnboardingPage(preferences: preferences)));
      await tester.pumpAndSettle();
      final local = AppLocalizations.of(
        tester.element(find.byType(OnboardingPage)),
      )!;
      final after = find.text(local.continueLabel);
      await tester.ensureVisible(after);
      await tester.pumpAndSettle();
      expect(find.text(local.firstProfessionRequired), findsNothing);
      await tester.tap(after);
      await tester.pumpAndSettle();
      expect(written['name'], 'Test User');
      expect(written['week'], 'monday');
      expect(written['accent'], 'teal');
      expect(written['welcome'], 'true');
      expect(written.containsKey('complete'), isFalse);
      expect(continued, isTrue);
    },
  );

  testWidgets(
    'template-only field menus protect required fields and allow reordering',
    (tester) async {
      final required = nursingPilot.fields.firstWhere(nursingReportRules.needs);
      final fields = [
        required,
        ...nursingPilot.fields.where((f) => f != required),
      ];
      final active = LayoutRevision(
        collectionId: 'demo',
        version: 1,
        fields: fields,
      );
      final editor = EditFieldsPage(
        title: 'Nursing',
        layout: active,
        arrangementOnly: true,
        suppliedLayout: active,
        library: FieldLibrary([], categories: {}),
        maxActiveFields: 20,
        reportExclusions: const {},
        requiredReportDefinitions: nursingReportRules.requiredDefinitions,
        save: (_, _) async => active.collectionId,
      );
      await tester.pumpWidget(_app(editor));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-add-field')), findsNothing);
      await tester.tap(find.byKey(ValueKey('menu-${fields.first.id}')));
      await tester.pumpAndSettle();
      bool enabled(String name) => tester
          .widget<PopupMenuItem>(
            find.ancestor(
              of: find.text(name),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          )
          .enabled;
      expect(enabled('Field settings'), isFalse);
      expect(enabled('Delete field'), isFalse);
      expect(enabled('Remove from reports'), isFalse);
      expect(enabled('Move up'), isFalse);
      expect(enabled('Move down'), isTrue);
    },
  );
}
