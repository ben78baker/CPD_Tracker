import 'package:cpd_tracker/cpd_creation/nursing_pilot.dart';
import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/onboarding_page.dart';
import 'package:cpd_tracker/recording_editor/edit_fields_page.dart';
import 'package:cpd_tracker/recording_engine/field_library.dart';
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
  @override
  Future<Map<String, String>> loadHostState(String namespace) async => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    'template layout mode hides field settings, library and duplication',
    (tester) async {
      final fields = nursingPilot.fields;
      final active = LayoutRevision(
        collectionId: 'demo',
        version: 1,
        fields: fields,
      );
      final editor = EditFieldsPage(
        title: 'Nursing',
        layout: active,
        arrangementOnly: true,
        suppliedFields: fields,
        library: FieldLibrary([], categories: {}),
        maxActiveFields: 20,
        save: (_) async => active,
      );
      await tester.pumpWidget(_app(editor));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-add-field')), findsNothing);
      await tester.tap(find.byKey(ValueKey('menu-${fields.first.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Field settings'), findsNothing);
      expect(find.text('Duplicate field'), findsNothing);
      expect(find.text('Move down'), findsOneWidget);
    },
  );
}
