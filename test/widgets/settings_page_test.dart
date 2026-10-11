import 'package:cpd_tracker/home_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/main.dart';
import 'package:cpd_tracker/settings_page.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsStore.instance.locale.value = null;
    SettingsStore.instance.appAccent.value = AppAccent.purple;
  });

  testWidgets('Home overflow navigates to Settings', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'professions': <String>['Electrician'],
    });

    await tester.pumpWidget(_testApp(home: const HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-menu-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-language')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-app-colour')), findsOneWidget);
  });

  testWidgets('MyApp updates its theme immediately after colour selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_complete': true,
    });
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary,
      AppBrandColors.fromAccent(AppAccent.purple).accent,
    );

    await SettingsStore.instance.setAppAccent(AppAccent.indigo);
    await tester.pump();

    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary,
      AppBrandColors.fromAccent(AppAccent.indigo).accent,
    );
  });

  testWidgets('language, week start and Reset Tips work in Settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'qr_hint_dismissed': true,
    });
    await tester.pumpWidget(_testApp(home: const SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('German'));
    await tester.pumpAndSettle();
    expect(await SettingsStore.instance.getLocaleCode(), 'de');

    await tester.tap(find.byKey(const ValueKey('settings-week-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(await SettingsStore.instance.getWeekStart(), 'monday');

    final reset = find.byKey(const ValueKey('reset-tips-action'));
    await tester.fling(find.byType(ListView), const Offset(0, -1200), 1200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Tips').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(await SettingsStore.instance.isQrHintDismissed(), isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  for (final locale in const <Locale>[Locale('de'), Locale('pt')]) {
    testWidgets(
      'Settings supports narrow width and large text in ${locale.languageCode}',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _testApp(
            locale: locale,
            textScaler: const TextScaler.linear(2),
            home: const SettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _testApp({
  required Widget home,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ValueListenableBuilder<AppAccent>(
    valueListenable: SettingsStore.instance.appAccent,
    builder: (context, accent, _) => MaterialApp(
      theme: AppTheme.forAccent(accent),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: home,
      ),
    ),
  );
}
