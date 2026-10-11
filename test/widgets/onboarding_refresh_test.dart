import 'dart:ui' show Tristate;

import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/onboarding_page.dart';
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SettingsStore.instance.locale.value = null;
    SettingsStore.instance.appAccent.value = AppAccent.purple;
  });

  testWidgets('onboarding defaults to purple and applies a new colour live', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_onboardingApp());
    await tester.pumpAndSettle();

    final purple = find.bySemanticsLabel('Purple');
    expect(purple, findsOneWidget);
    expect(
      tester.getSemantics(purple).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    final logo = tester.widget<Image>(find.byType(Image));
    expect(
      (logo.image as AssetImage).assetName,
      'assets/icon/1024x1024_app_icon.png',
    );

    final blue = find.byKey(const ValueKey('app-colour-blue'));
    await tester.ensureVisible(blue);
    await tester.tap(blue);
    await tester.pumpAndSettle();

    expect(SettingsStore.instance.appAccent.value, AppAccent.blue);
    expect(await SettingsStore.instance.getAppAccent(), AppAccent.blue);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary,
      AppBrandColors.fromAccent(AppAccent.blue).accent,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Blue'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  for (final locale in const <Locale>[Locale('de'), Locale('pt')]) {
    testWidgets(
      'onboarding supports narrow width and large text in ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _onboardingApp(
            locale: locale,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(OnboardingPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _onboardingApp({
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
        child: const OnboardingPage(),
      ),
    ),
  );
}
