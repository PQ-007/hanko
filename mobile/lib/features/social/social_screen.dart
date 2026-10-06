import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../battle/hero.dart';
import '../battle/sprite_view.dart';
import '../decks/word_actions.dart' show toast;
import '../pvp/pvp_screen.dart';
import 'social_api.dart';

/// The friends tab: friends and their activity, the leaderboard, and duels.
class SocialScreen extends StatelessWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(T.socialTitle),
          bottom: const TabBar(
            tabs: [
              Tab(text: T.socialTabFriends),
              Tab(text: T.socialTabBoard),
              Tab(text: T.socialTabDuel),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_FriendsView(), _BoardView(), DuelLobbyView()],
        ),
      ),
    );
  }
}

void _refreshSocial(WidgetRef ref) {
  ref.invalidate(myProfileProvider);
  ref.invalidate(friendOverviewProvider);
  ref.invalidate(friendRequestsProvider);
}

// ---- Friends -------------------------------------------------------------------

class _FriendsView extends ConsumerStatefulWidget {
  const _FriendsView();

  @override
  ConsumerState<_FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends ConsumerState<_FriendsView> {
  final _add = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final h = _add.text.trim();
    if (h.isEmpty) return;
    setState(() => _busy = true);
    try {
      final status = await ref.read(socialApiProvider).sendRequest(h);
      if (!mounted) return;
      toast(context, switch (status) {
        'sent' => T.socialSent,
        'accepted' => T.socialAccepted,
        'already' => T.socialAlready,
        'self' => T.socialSelf,
        _ => T.socialNotFound,
      });
      if (status == 'sent' || status == 'accepted') _add.clear();
      _refreshSocial(ref);
    } catch (_) {
      if (mounted) toast(context, T.socialUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider);
    final overview = ref.watch(friendOverviewProvider);
    final requests =
        ref.watch(friendRequestsProvider).value ?? const <FriendRequest>[];

    return RefreshIndicator(
      onRefresh: () async {
        _refreshSocial(ref);
        await ref
            .read(friendOverviewProvider.future)
            .catchError((_) => <FriendRow>[]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          me.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text(
              T.socialUnavailable,
              style: TextStyle(color: context.hk.inkMute),
            ),
            data: (p) => p.handle == null
                ? const _HandleCard()
                : _MyHandle(handle: p.handle!),
          ),
          const SizedBox(height: 14),
          if (me.value?.handle != null) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _add,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: T.socialAddFriend,
                      hintText: T.socialAddHint,
                    ),
                    onSubmitted: (_) => _sendRequest(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _sendRequest,
                  child: const Text(T.socialAdd),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (requests.isNotEmpty) ...[
            Text(
              T.socialRequests,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            for (final r in requests) _RequestTile(r: r),
            const SizedBox(height: 14),
          ],
          overview.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Text(
              T.socialUnavailable,
              style: TextStyle(color: context.hk.inkMute),
            ),
            data: (rows) {
              final mine = rows.where((r) => r.isMe).toList();
              final friends = rows.where((r) => !r.isMe).toList()
                ..sort((a, b) => (b.xpWeek ?? -1).compareTo(a.xpWeek ?? -1));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in mine) _ActivityCard(row: r),
                  const SizedBox(height: 10),
                  if (friends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        T.socialNoFriends,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.hk.inkMute),
                      ),
                    ),
                  for (final r in friends) ...[
                    _ActivityCard(row: r),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HandleCard extends ConsumerStatefulWidget {
  const _HandleCard();

  @override
  ConsumerState<_HandleCard> createState() => _HandleCardState();
}

class _HandleCardState extends ConsumerState<_HandleCard> {
  final _c = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(socialApiProvider).setHandle(_c.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (err) {
        null => null,
        HandleError.format => T.socialHandleFormat,
        HandleError.taken => T.socialHandleTaken,
        HandleError.other => T.socialHandleFailed,
      };
    });
    if (err == null) _refreshSocial(ref);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              T.socialPickHandle,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              T.socialPickHandleDesc,
              style: TextStyle(fontSize: 12, color: context.hk.inkMute),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _c,
              autocorrect: false,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: T.socialHandleLabel,
                prefixText: '@',
                helperText: T.socialHandleFormat,
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text(T.socialSave),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyHandle extends StatelessWidget {
  const _MyHandle({required this.handle});
  final String handle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '@$handle',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        IconButton(
          tooltip: T.socialAddFriend,
          icon: const Icon(Icons.share),
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: T.socialShareInvite(handle)),
          ),
        ),
      ],
    );
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.r});
  final FriendRequest r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read when a button is pressed, not while building the row.
    SocialApi api() => ref.read(socialApiProvider);
    Future<void> act(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {
        if (context.mounted) toast(context, T.socialUnavailable);
      }
      _refreshSocial(ref);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: _Avatar(name: r.name ?? r.handle ?? '?'),
        title: Text(r.name ?? '@${r.handle}'),
        subtitle: Text(
          r.incoming
              ? '@${r.handle ?? ''}'
              : '@${r.handle ?? ''} · ${T.socialOutgoing}',
        ),
        trailing: r.incoming
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: T.socialDecline,
                    icon: const Icon(Icons.close),
                    onPressed: () => act(() => api().respond(r.otherId, false)),
                  ),
                  IconButton.filled(
                    tooltip: T.socialAccept,
                    icon: const Icon(Icons.check),
                    onPressed: () => act(() => api().respond(r.otherId, true)),
                  ),
                ],
              )
            : TextButton(
                onPressed: () => act(() => api().remove(r.otherId)),
                child: const Text(T.socialCancelRequest),
              ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.image, this.radius = 20});
  final String name;
  final String? image;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final img = image;
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.hk.sealTint,
      foregroundImage: img != null && img.startsWith('https://')
          ? NetworkImage(img)
          : null,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: HankoColors.seal,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

/// One person's day: level and XP, what they added and reviewed today, what
/// they've learned, and the kanji they wrote from memory most recently.
class _ActivityCard extends ConsumerWidget {
  const _ActivityCard({required this.row});
  final FriendRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row;
    final xp = r.xpTotal ?? 0;
    final lv = levelFor(xp);
    final from = xpForLevel(lv), to = xpForLevel(lv + 1);
    final muted = TextStyle(fontSize: 12, color: context.hk.inkMute);

    Widget chip(String text, IconData icon) => Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: Chip(
        avatar: Icon(icon, size: 16, color: HankoColors.seal),
        label: Text(text, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: context.hk.lineSoft),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: r.isMe ? HankoColors.seal : context.hk.lineSoft,
          width: r.isMe ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                r.isMe
                    ? SizedBox.square(
                        dimension: 44,
                        child: SpriteView(
                          slug: ref.watch(heroProvider),
                          size: 44,
                        ),
                      )
                    : _Avatar(name: r.displayName, image: r.image, radius: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.isMe
                            ? '${r.displayName} (${T.socialYou})'
                            : r.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        [
                          if (r.handle != null) '@${r.handle}',
                          if (r.shares) T.socialLevel(lv),
                          if (r.shares && r.elo != null) T.socialElo(r.elo!),
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
                if (!r.isMe)
                  PopupMenuButton<String>(
                    onSelected: (_) async {
                      try {
                        await ref.read(socialApiProvider).remove(r.userId);
                      } catch (_) {}
                      _refreshSocial(ref);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text(T.socialRemove),
                      ),
                    ],
                  ),
              ],
            ),
            if (!r.shares)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(T.socialHidden, style: muted),
              )
            else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: to == from ? 1 : (xp - from) / (to - from),
                        minHeight: 7,
                        backgroundColor: context.hk.lineSoft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    T.socialXp(xp),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 8),
              Text(T.socialToday, style: muted),
              const SizedBox(height: 4),
              Wrap(
                children: [
                  chip(
                    T.socialAddedToday(r.addedToday ?? 0),
                    Icons.add_circle_outline,
                  ),
                  chip(
                    T.socialReviewedToday(r.reviewedToday ?? 0),
                    Icons.replay,
                  ),
                  chip(
                    T.socialWordsLearned(r.wordsLearned ?? 0),
                    Icons.school_outlined,
                  ),
                  chip(
                    T.socialKanjiLearned(r.kanjiLearned ?? 0),
                    Icons.draw_outlined,
                  ),
                ],
              ),
              if (r.recentKanji.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: [
                    for (final k in r.recentKanji)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.hk.sealTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          k,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Leaderboard ---------------------------------------------------------------

enum _Rank { week, total, elo }

class _BoardView extends ConsumerStatefulWidget {
  const _BoardView();

  @override
  ConsumerState<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends ConsumerState<_BoardView> {
  _Rank _by = _Rank.week;

  int _score(FriendRow r) => switch (_by) {
    _Rank.week => r.xpWeek ?? 0,
    _Rank.total => r.xpTotal ?? 0,
    _Rank.elo => r.elo ?? 1000,
  };

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(friendOverviewProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(friendOverviewProvider);
        await ref
            .read(friendOverviewProvider.future)
            .catchError((_) => <FriendRow>[]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SegmentedButton<_Rank>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Rank.week, label: Text(T.socialBoardWeek)),
              ButtonSegment(
                value: _Rank.total,
                label: Text(T.socialBoardTotal),
              ),
              ButtonSegment(value: _Rank.elo, label: Text(T.socialBoardElo)),
            ],
            selected: {_by},
            onSelectionChanged: (s) => setState(() => _by = s.single),
          ),
          const SizedBox(height: 6),
          Text(
            _by == _Rank.elo ? T.socialBoardEloNote : T.socialXpNote,
            style: TextStyle(fontSize: 11, color: context.hk.inkMute),
          ),
          const SizedBox(height: 10),
          overview.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Text(
              T.socialUnavailable,
              style: TextStyle(color: context.hk.inkMute),
            ),
            data: (rows) {
              // Only people whose numbers are shared can be ranked.
              final ranked = rows.where((r) => r.shares).toList()
                ..sort((a, b) => _score(b).compareTo(_score(a)));
              if (ranked.length < 2) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    T.socialBoardEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.hk.inkMute),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < ranked.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      color: ranked[i].isMe ? context.hk.sealTint : null,
                      child: ListTile(
                        leading: SizedBox(
                          width: 36,
                          child: Center(
                            child: Text(
                              i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}',
                              style: TextStyle(
                                fontSize: i < 3 ? 24 : 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          ranked[i].isMe
                              ? '${ranked[i].displayName} (${T.socialYou})'
                              : ranked[i].displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (ranked[i].handle != null)
                              '@${ranked[i].handle}',
                            T.socialLevel(levelFor(ranked[i].xpTotal ?? 0)),
                          ].join(' · '),
                        ),
                        trailing: Text(
                          _by == _Rank.elo
                              ? '${_score(ranked[i])}'
                              : T.socialXp(_score(ranked[i])),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
