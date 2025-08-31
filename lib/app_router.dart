import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/home/home_page.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'home',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: HomePage()),
      ),
    ],
    errorPageBuilder: (context, state) => MaterialPage<void>(
      child: Scaffold(
        body: Center(
          child: Text('Router error: ${state.error}'),
        ),
      ),
    ),
    redirect: (context, state) {
      // Place future first-run / onboarding redirects here.
      return null;
    },
    observers: const <NavigatorObserver>[],
  );
}