import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../battle/hero.dart';
import '../battle/rules.dart' show minWordsForBattle;
import '../battle/sprite_view.dart';
import '../battle/sprites.dart' show monsterBag;
import '../duel/duel_api.dart';
import '../duel/duel_rules.dart';
import '../duel/duel_screen.dart';
import '../duel/opponent.dart';
import '../duel/remote_launch.dart';

/// A friend to challenge, set from elsewhere (the friends tab's "Тулах"):
/// the lobby picks it up, sends the invitation and shows the waiting room.
final pendingDuelChallengeProvider = NotifierProvider<PendingChallenge, FriendLite?>(PendingChallenge.new);

class PendingChallenge extends Notifier<FriendLite?> {
  @override
  FriendLite? build() => null;

  // ignore: use_setters_to_change_properties
  void set(FriendLite? f) => state = f;
}

/// Challenges waiting for me (0030), polled — the app has no push. Shared by
/// the lobby and the app-wide banner.
final duelInvitesProvider = StreamProvider.autoDispose<List<DuelInvite>>((ref) async* {
  final api = ref.watch(duelApiProvider);
  while (true) {
    try {
      yield await api.invites();
    } catch (_) {
      yield const [];
    }
    await Future<void>.delayed(const Duration(seconds: 12));
  }
});

/// The duel lobby (web DuelLobby.tsx), the Тулаан section of the friends tab: a bot at three levels with no network
/// at all, or a friend by invite code (PVP.md: no queue — with a handful of
/// players a queue is an infinite spinner).
class DuelLobbyView extends ConsumerStatefulWidget {
  const DuelLobbyView({super.key});

  @override
  ConsumerState<DuelLobbyView> createState() => _DuelLobbyViewState();
}

class _DuelLobbyViewState extends ConsumerState<DuelLobbyView> {
  final _code = TextEditingController();
  MatchRow? _lobby;
  List<FriendLite> _friends = const [];

  /// Who the open invitation is to (the waiting room says so).
  String? _invitee;

  @override
  void initState() {
    super.initState();
    ref.read(duelApiProvider).friends().then((f) {
      if (mounted) setState(() => _friends = f);
    }, onError: (_) {});
    // A challenge chosen on the friends tab before this tab existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePending());
  }

  void _takePending() {
    final f = ref.read(pendingDuelChallengeProvider);
    if (f == null || !mounted) return;
    ref.read(pendingDuelChallengeProvider.notifier).set(null);
    _invite(f);
  }

  Future<void> _invite(FriendLite f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await ref.read(duelApiProvider).inviteFriend(f.userId, ref.read(heroProvider));
      if (!mounted) return;
      setState(() {
        _lobby = m;
        _invitee = f.label;
      });
      _waitForGuest(m.id);
    } catch (_) {
      if (mounted) setState(() => _error = T.duelInviteFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(DuelInvite inv) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await ref.read(duelApiProvider).acceptInvite(inv.matchId, ref.read(heroProvider));
      if (!mounted) return;
      _startRemote(m);
    } catch (_) {
      if (mounted) setState(() => _error = T.duelInviteAcceptFailed);
    } finally {
      ref.invalidate(duelInvitesProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(DuelInvite inv) async {
    try {
      await ref.read(duelApiProvider).declineInvite(inv.matchId);
    } catch (_) {}
    ref.invalidate(duelInvitesProvider);
  }
  bool _busy = false;
  String? _error;
  Timer? _poll;
  RealtimeChannel? _channel;

  @override
  void dispose() {
    _stopWaiting();
    _code.dispose();
    super.dispose();
  }

  // ---- Bot ---------------------------------------------------------------------

  void _playBot(BotDifficulty d) {
    final hero = ref.read(heroProvider);
    final (name, _) = _botLabel(d);
    _openDuel(
      () => BotOpponent(
        name: name,
        slug: monsterBag.pick(exclude: hero),
        profile: botProfiles[d]!,
      ),
    );
  }

  // ---- Friend ------------------------------------------------------------------

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await ref
          .read(duelApiProvider)
          .createMatch(ref.read(heroProvider));
      if (!mounted) return;
      setState(() => _lobby = m);
      _waitForGuest(m.id);
    } catch (_) {
      if (mounted) setState(() => _error = T.duelCreateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await ref
          .read(duelApiProvider)
          .joinMatch(code, ref.read(heroProvider));
      if (!mounted) return;
      _code.clear();
      _startRemote(m);
    } catch (_) {
      if (mounted) setState(() => _error = T.duelJoinFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The host waits on their match row until someone joins: Realtime says so,
  /// and a slow poll covers a channel that never connected.
  void _waitForGuest(String matchId) {
    final api = ref.read(duelApiProvider);
    Future<void> refresh() async {
      try {
        final m = await api.match(matchId);
        if (!mounted || m == null || _lobby?.id != matchId) return;
        if (m.status == 'active') {
          _startRemote(m);
        } else if (m.status != 'lobby') {
          _stopWaiting();
          setState(() => _lobby = null);
        }
      } catch (_) {}
    }

    _poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    _channel = api.db
        .channel('lobby:$matchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: matchId,
          ),
          callback: (_) => refresh(),
        )
        .subscribe();
  }

  void _stopWaiting() {
    _poll?.cancel();
    _poll = null;
    final c = _channel;
    _channel = null;
    if (c != null) ref.read(duelApiProvider).db.removeChannel(c);
  }

  Future<void> _cancelLobby() async {
    final m = _lobby;
    _stopWaiting();
    setState(() => _lobby = null);
    if (m != null) {
      try {
        // concede: if a guest joined in the same instant, they win — not us.
        await ref.read(duelApiProvider).concede(m.id);
      } catch (_) {
        // Server without 0026: a lobby nobody joined has no winner anyway.
        try {
          await ref.read(duelApiProvider).forfeit(m.id);
        } catch (_) {}
      }
    }
  }

  void _startRemote(MatchRow m) {
    _stopWaiting();
    setState(() {
      _lobby = null;
      _invitee = null;
    });
    // Loads who the opponent is and your record, then opens on the intro.
    openRemoteDuel(context, ref, m);
  }

  void _openDuel(OpponentDriver Function() make, {String? matchId}) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => DuelScreen(makeOpponent: make, matchId: matchId),
      ),
    );
  }

  (String, String) _botLabel(BotDifficulty d) => switch (d) {
    BotDifficulty.rookie => (T.duelBotRookie, T.duelBotRookieDesc),
    BotDifficulty.rival => (T.duelBotRival, T.duelBotRivalDesc),
    BotDifficulty.master => (T.duelBotMaster, T.duelBotMasterDesc),
  };

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingDuelChallengeProvider, (_, next) {
      if (next != null) _takePending();
    });
    final invites = ref.watch(duelInvitesProvider).value ?? const <DuelInvite>[];
    final hero = ref.watch(heroProvider);
    final words = ref.watch(allWordsProvider).value;
    final tooFew = words != null && words.length < minWordsForBattle;
    final lobby = _lobby;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: HankoColors.arena,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpriteView(slug: hero, size: 110),
              const Text(
                'VS',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              SpriteView(
                slug: hero == 'black-knight-a' ? 'knight' : 'black-knight-a',
                size: 110,
                flip: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          T.duelLobbyTitle,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(
          T.duelNotScheduled,
          style: TextStyle(fontSize: 12, color: context.hk.inkMute),
        ),
        if (tooFew) ...[
          const SizedBox(height: 16),
          Text(
            T.notEnoughWordsBattle,
            style: TextStyle(color: context.hk.inkSoft),
          ),
        ] else ...[
          if (invites.isNotEmpty && lobby == null) ...[
            const SizedBox(height: 16),
            Text(T.duelInvitesTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final inv in invites) ...[
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: context.hk.seal, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Icon(Icons.sports_kabaddi, color: context.hk.sealText),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            inv.rematch ? T.duelRematchFrom(inv.label) : T.duelInviteFrom(inv.label),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : () => _accept(inv),
                            child: const Text(T.duelInviteAccept),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: () => _decline(inv), child: const Text(T.duelInviteDecline)),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 16),
          Text(
            T.duelBotSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            T.duelBotDesc,
            style: TextStyle(fontSize: 12, color: context.hk.inkMute),
          ),
          const SizedBox(height: 8),
          for (final d in BotDifficulty.values) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(switch (d) {
                  BotDifficulty.rookie => Icons.sentiment_satisfied_alt,
                  BotDifficulty.rival => Icons.sports_martial_arts,
                  BotDifficulty.master => Icons.local_fire_department,
                }, color: context.hk.sealText),
                title: Text(
                  _botLabel(d).$1,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_botLabel(d).$2),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _playBot(d),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          Text(
            T.duelFriendSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (lobby != null)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: lobby.invitedId != null
                    ? Column(children: [
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          _invitee != null ? T.duelInviteSentTo(_invitee!) : T.duelWaitingGuest,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(T.duelInviteSentDesc,
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.hk.inkMute)),
                        TextButton(onPressed: _cancelLobby, child: const Text(T.duelCancel)),
                      ])
                    : Column(
                  children: [
                    const Text(T.duelCodeLabel),
                    SelectableText(
                      lobby.joinCode ?? '----',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                    Text(
                      T.duelCodeShare,
                      style: TextStyle(fontSize: 12, color: context.hk.inkMute),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: T.duelCodeShare,
                          icon: const Icon(Icons.copy),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: lobby.joinCode ?? ''),
                          ),
                        ),
                        IconButton(
                          tooltip: T.duelCodeShare,
                          icon: const Icon(Icons.share),
                          onPressed: () => SharePlus.instance.share(
                            ShareParams(text: lobby.joinCode ?? ''),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text(T.duelWaitingGuest),
                    TextButton(
                      onPressed: _cancelLobby,
                      child: const Text(T.duelCancel),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(T.duelInviteFriendSection,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.hk.inkSoft)),
            const SizedBox(height: 6),
            if (_friends.isEmpty)
              Text(T.duelNoFriends, style: TextStyle(fontSize: 12, color: context.hk.inkMute))
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, f) in _friends.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: context.hk.sealTint,
                          child: Text(
                            f.label.replaceAll('@', '').characters.first.toUpperCase(),
                            style: TextStyle(color: context.hk.sealText, fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: f.name != null && f.handle != null ? Text('@${f.handle}') : null,
                        trailing: FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _invite(f),
                          icon: const Icon(Icons.sports_kabaddi, size: 16),
                          label: const Text(T.duelInviteBtn),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text(T.duelCreate),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: T.duelCodeLabel,
                      hintText: T.duelCodePlaceholder,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _join(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _busy ? null : _join,
                  child: const Text(T.duelJoin),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
        ],
      ],
    );
  }
}
