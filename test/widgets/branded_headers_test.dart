import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:cpd_tracker/widgets/branded_headers.dart';
import 'package:cpd_tracker/widgets/profession_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _localizedApp({required Locale locale, required Widget home}) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: home,
    ),
  );
}

void main() {
  testWidgets('page header remains usable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const title =
        'Inspection, Prüfung und berufliche Weiterbildung für Fachkräfte';
    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('de'),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: BrandedPageHeader(
              title: title,
              icon: Icons.track_changes_rounded,
            ),
          ),
        ),
      ),
    );

    expect(find.text(title), findsOneWidget);
    expect(find.byIcon(Icons.track_changes_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('brand header uses the real CPD Progress Tracker asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: const Scaffold(
          body: BrandedPageHeader.brand(title: 'CPD Progress Tracker'),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/icon/1024x1024_app_icon.png',
    );
  });

  for (final locale in const [Locale('de'), Locale('pt')]) {
    testWidgets(
      'profession card adapts ${locale.languageCode} actions for large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var addPressed = false;
        const profession =
            'Elektroinstallation, Prüfung und fortlaufende berufliche Entwicklung';

        await tester.pumpWidget(
          _localizedApp(
            locale: locale,
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ProfessionCard(
                  name: profession,
                  target: null,
                  refreshToken: 0,
                  computeCompleted: (_) async => 0,
                  onSetTarget: () {},
                  onAdd: () => addPressed = true,
                  onScan: () {},
                  onView: () {},
                  onSearch: () {},
                  onRename: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text(profession), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(Icons.add));
        expect(addPressed, isTrue);
      },
    );
  }
}
