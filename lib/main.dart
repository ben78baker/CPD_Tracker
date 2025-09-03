import 'package:flutter/material.dart';
import 'home_page.dart';
import 'qr_scan_page.dart';
import 'onboarding_page.dart';
import 'settings_store.dart';


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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
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