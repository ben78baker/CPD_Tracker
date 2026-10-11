import 'package:cpd_tracker/home_page.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:cpd_tracker/widgets/branded_headers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home uses a compact accessible branded header', (tester) async {
    SharedPreferences.setMockInitialValues({
      'professions': <String>['Electrician'],
    });
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BrandedPageHeader), findsNothing);

    final logo = find.byKey(const ValueKey('home-brand-logo'));
    expect(tester.getSize(logo), const Size.square(34));
    final image = tester.widget<Image>(logo);
    expect(
      (image.image as AssetImage).assetName,
      'assets/icon/1024x1024_app_icon.png',
    );

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('home-app-title')),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.style?.fontSize, 21);
    expect(title.style?.fontWeight, FontWeight.w700);

    final search = find.byKey(const ValueKey('home-search-action'));
    final menu = find.byKey(const ValueKey('home-menu-action'));
    expect(tester.getSize(search), const Size.square(48));
    expect(tester.getSize(menu), const Size.square(48));
    expect(find.byTooltip('Search all records'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
