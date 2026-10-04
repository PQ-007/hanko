import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_router.dart';
import 'core/config.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Config.isConfigured) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabasePublishableKey,
    );
  }

  runApp(const ProviderScope(child: HankoApp()));
}

class HankoApp extends StatelessWidget {
  const HankoApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Config.isConfigured) {
      return MaterialApp(
        title: 'Hanko',
        debugShowCheckedModeBanner: false,
        theme: buildHankoTheme(),
        home: const _MissingConfig(),
      );
    }
    return const _RoutedApp();
  }
}

/// Split out so the router (which reads the Supabase client) is only built
/// once Supabase has been initialised.
class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Hanko',
      debugShowCheckedModeBanner: false,
      theme: buildHankoTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Missing Supabase config.\n\n'
            'Copy env.example.json to env.json, fill it in, and run with:\n\n'
            'flutter run --dart-define-from-file=env.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
