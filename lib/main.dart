import 'package:flutter/material.dart';
import 'home_page.dart';
import 'qr_scan_page.dart';
import 'onboarding_page.dart';
import 'settings_store.dart';

final ThemeData appTheme = ThemeData(
  // Blue across the app; FilledButtons will use this automatically
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  useMaterial3: true,
  textTheme: Typography.blackMountainView.apply(
    fontFamily: 'Roboto', // or another font family available in Flutter
    bodyColor: Colors.black,
    displayColor: Colors.black,
  ).copyWith(
    bodyMedium: const TextStyle(fontSize: 16.0),
    titleMedium: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
    labelLarge: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.w500),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: ButtonStyle(
      foregroundColor: const WidgetStatePropertyAll(Colors.blue),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: const WidgetStatePropertyAll(Colors.blue),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    ),
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

   Future<bool> _shouldStartOnboarding() async {
    // Start onboarding if not completed yet
    final done = await SettingsStore.instance.isOnboardingComplete();
    return !done;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CPD Tracker',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: FutureBuilder<bool>(
        future: _shouldStartOnboarding(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return const OnboardingPage();
          }
          final startOnboarding = snapshot.data ?? true;
          return startOnboarding ? const OnboardingPage() : const HomePage();
        },
      ),
      routes: {
        '/onboarding': (_) => const OnboardingPage(),
        '/home': (_) => const HomePage(),
        '/scan': (_) => const QrScanPage(profession: ''),
      },
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => const HomePage(),
      ),
    );
  }
}