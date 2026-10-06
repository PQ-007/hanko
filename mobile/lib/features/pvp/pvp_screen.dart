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
    final api = ref.read(duelApiProvider);
    final me = api.userId;
    final isHost = m.hostId == me;
    final opponentId = isHost ? m.guestId : m.hostId;
    if (opponentId == null) return;
    setState(() => _lobby = null);
    _openDuel(
      () => RemoteOpponent(
        api: api,
        matchId: m.id,
        opponentId: opponentId,
        name: T.multiplayerTitle,
        slug: (isHost ? m.guestCharacter : m.hostCharacter) ?? 'knight',
        baselineMs: isHost ? m.guestBaselineMs : m.hostBaselineMs,
      ),
      matchId: m.id,
    );
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
                }, color: HankoColors.seal),
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
                child: Column(
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
