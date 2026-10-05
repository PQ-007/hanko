import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/repository.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/battle/battle_screen.dart';
import 'features/capture/capture_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/settings_screen.dart';
import 'features/library/deck_detail_screen.dart';
import 'features/library/library_screen.dart';
import 'features/pvp/pvp_screen.dart';
import 'features/review/leech_rescue_screen.dart';
import 'features/review/review_screen.dart';
import 'features/review/speed_round_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/stats/stats_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Re-runs the router's redirect whenever the session changes — a sign-out on
/// another device or a refresh failure has to land on the sign-in screen
/// without anything else noticing first.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(GoTrueClient auth) {
    _sub = auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Path helpers, so screens don't spell route strings by hand.
class Routes {
  const Routes._();

  static const home = '/home';
  static const stats = '/stats';
  static const pvp = '/pvp';
  static const library = '/library';
  static String deck(String id) => '/library/deck/$id';
  static const settings = '/settings';
  static const speed = '/speed';
  static const leech = '/leech';
  static const capture = '/capture';

  /// Monster Hunt. [free] practises any card as a drill (nothing rescheduled).
  static String hunt({String? deckId, bool free = false}) => Uri(
        path: '/hunt',
        queryParameters: {
          'deck': ?deckId,
          if (free) 'mode': 'free',
        },
      ).toString();

  static String review({String? deckId, String? deckName}) => Uri(
        path: '/review',
        queryParameters: {
          'deck': ?deckId,
          'name': ?deckName,
        },
      ).toString();
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final listenable = _AuthListenable(auth);
  ref.onDispose(listenable.dispose);

  // Full-screen routes sit on the root navigator, above the shell: no nav bar
  // during a session, and finishing one returns to whichever tab started it.
  GoRoute fullScreen(String path, Widget Function(GoRouterState) build) => GoRoute(
        path: path,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => build(state),
      );

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    refreshListenable: listenable,
    redirect: (context, state) {
      final signedIn = auth.currentSession != null;
      final atSignIn = state.matchedLocation == '/signin';
      if (!signedIn) return atSignIn ? null : '/signin';
      if (atSignIn) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.stats, builder: (_, _) => const StatsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.pvp, builder: (_, _) => const PvpScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.library,
              builder: (_, _) => const LibraryScreen(),
              routes: [
                GoRoute(
                  path: 'deck/:id',
                  builder: (_, state) =>
                      DeckDetailScreen(deckId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
        ],
      ),
      fullScreen(Routes.settings, (_) => const SettingsScreen()),
      fullScreen(
        '/review',
        (s) => ReviewScreen(
          deckId: s.uri.queryParameters['deck'],
          deckName: s.uri.queryParameters['name'],
        ),
      ),
      fullScreen(
        '/hunt',
        (s) => BattleScreen(
          deckId: s.uri.queryParameters['deck'],
          free: s.uri.queryParameters['mode'] == 'free',
        ),
      ),
      fullScreen(Routes.capture, (_) => const CaptureScreen()),
      fullScreen(Routes.speed, (s) => SpeedRoundScreen(deckId: s.uri.queryParameters['deck'])),
      fullScreen(Routes.leech, (s) => LeechRescueScreen(deckId: s.uri.queryParameters['deck'])),
    ],
  );
});
