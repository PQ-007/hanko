import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/repository.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/decks/deck_list_screen.dart';

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
    return MaterialApp(
      title: 'Hanko',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F2937)),
        useMaterial3: true,
      ),
      home: Config.isConfigured ? const AuthGate() : const _MissingConfig(),
    );
  }
}

/// Shows the deck list when signed in and the sign-in screen when not, and
/// keeps following the session rather than checking once at startup — a token
/// refresh failure or a sign-out on another device has to land here too.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final session = Supabase.instance.client.auth.currentSession;

    return auth.when(
      loading: () => session == null
          ? const SignInScreen()
          : const DeckListScreen(),
      error: (_, _) => const SignInScreen(),
      data: (state) => state.session == null
          ? const SignInScreen()
          : const DeckListScreen(),
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
