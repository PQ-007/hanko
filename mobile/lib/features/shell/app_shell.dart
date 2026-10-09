import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../decks/word_actions.dart' show toast;
import '../battle/hero.dart';
import '../pvp/pvp_screen.dart' show duelInvitesProvider;
import '../duel/remote_launch.dart';
import '../duel/duel_api.dart';
import 'package:go_router/go_router.dart';

import '../../core/offline_words.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'action_sheet.dart';

/// Four tabs around a center action button.
///
/// Each tab is its own go_router branch, so switching tabs keeps its scroll
/// position and navigation stack. The center slot is a NavigationBar
/// destination drawn as a raised button; selecting it opens the action sheet
/// and never becomes the selected tab.
///
/// Also where words captured offline get sent: on start and whenever the app
/// comes back to the foreground, which is when a connection has most likely
/// returned.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flushWords();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flushWords();
  }

  Future<void> _flushWords() async {
    try {
      final sent = await ref.read(wordOutboxProvider).flush();
      if (sent > 0 && mounted) ref.refreshLibrary();
    } catch (_) {}
  }

  static const _center = 2;

  int get _navIndex => shell.currentIndex < _center ? shell.currentIndex : shell.currentIndex + 1;

  void _onSelect(BuildContext context, WidgetRef ref, int navIndex) {
    if (navIndex == _center) {
      showActionSheet(context, ref);
      return;
    }
    final branch = navIndex < _center ? navIndex : navIndex - 1;
    // Tapping the current tab again pops it back to its root, the usual
    // bottom-nav convention.
    shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    // A friend's challenge wherever you are — except on the duel tab itself
    // (branch 2), whose lobby lists the same invitations.
    final invites = ref.watch(duelInvitesProvider).value ?? const [];
    final invite = shell.currentIndex == 2 || invites.isEmpty ? null : invites.first;
    return Scaffold(
      body: Stack(
        children: [
          shell,
          if (invite != null)
            Positioned(
              left: 12,
              right: 12,
              top: MediaQuery.of(context).padding.top + 8,
              child: _InviteBanner(invite: invite),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => _onSelect(context, ref, i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: T.navHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: T.navStats,
          ),
          NavigationDestination(
            icon: _CenterButton(),
            label: '',
            tooltip: T.navActions,
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_kabaddi_outlined),
            selectedIcon: Icon(Icons.sports_kabaddi),
            label: T.navPvp,
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: T.navLibrary,
          ),
        ],
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: context.hk.seal,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: context.hk.sealDark.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      // The app's own mark (the icon's ensō), not a generic plus.
      child: const Center(child: EnsoMark(size: 32)),
    );
  }
}

/// "X тантай тулахыг урьж байна" — accept opens the duel straight away.
class _InviteBanner extends ConsumerStatefulWidget {
  const _InviteBanner({required this.invite});
  final DuelInvite invite;

  @override
  ConsumerState<_InviteBanner> createState() => _InviteBannerState();
}

class _InviteBannerState extends ConsumerState<_InviteBanner> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final m = await ref.read(duelApiProvider).acceptInvite(widget.invite.matchId, ref.read(heroProvider));
      if (mounted) await openRemoteDuel(context, ref, m);
    } catch (_) {
      if (mounted) toast(context, T.duelInviteAcceptFailed);
    }
    ref.invalidate(duelInvitesProvider);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _decline() async {
    try {
      await ref.read(duelApiProvider).declineInvite(widget.invite.matchId);
    } catch (_) {}
    ref.invalidate(duelInvitesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final inv = widget.invite;
    return Material(
      color: hk.card,
      elevation: 8,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: hk.seal, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: hk.seal,
            child: const Icon(Icons.sports_kabaddi, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              inv.rematch ? T.duelRematchFrom(inv.label) : T.duelInviteFrom(inv.label),
              style: TextStyle(fontWeight: FontWeight.w700, color: hk.ink, height: 1.25),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _accept,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text(T.duelInviteAccept),
          ),
          IconButton(
            tooltip: T.duelInviteDecline,
            icon: Icon(Icons.close, color: hk.inkMute),
            onPressed: _decline,
          ),
        ]),
      ),
    );
  }
}
