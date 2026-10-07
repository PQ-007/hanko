import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_router.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../decks/word_actions.dart';
import 'audio_deck.dart';
import 'deck_player.dart';

/// The MP3s built on this phone. Shared with the library, which lists them.
final audioDecksProvider = FutureProvider<List<AudioDeck>>(
  (ref) => ref.watch(audioDeckStoreProvider).list(),
);

String formatDuration(int ms) {
  final s = (ms / 1000).round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// Every deck, with its audio if it has been made: create (with options),
/// play, share the MP3, rebuild, delete.
class AudioDecksScreen extends ConsumerStatefulWidget {
  const AudioDecksScreen({super.key});

  @override
  ConsumerState<AudioDecksScreen> createState() => _AudioDecksScreenState();
}

class _AudioDecksScreenState extends ConsumerState<AudioDecksScreen> {
  /// The deck being built, and how far along.
  String? _building;
  (int, int) _progress = (0, 0);

  Future<void> _create(Deck deck) async {
    final options = await showAudioOptions(context);
    if (options == null || !mounted) return;
    setState(() {
      _building = deck.id;
      _progress = (0, 0);
    });
    try {
      final words = [...await ref.read(repositoryProvider).words(deck.id)]
        ..sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
      if (words.isEmpty) {
        if (mounted) toast(context, T.audioNoWords);
        return;
      }
      final built = await ref
          .read(audioDeckStoreProvider)
          .build(
            deckId: deck.id,
            deckName: deck.name,
            words: words,
            options: options,
            onProgress: (done, total) {
              if (mounted) setState(() => _progress = (done, total));
            },
          );
      if (!mounted) return;
      if (built == null) {
        toast(context, T.audioDeckFailed);
      } else if (built.skipped > 0) {
        toast(context, T.audioSkipped(built.skipped));
      }
      ref.invalidate(audioDecksProvider);
    } catch (e) {
      if (mounted) toast(context, '${T.audioDeckFailed} $e');
    } finally {
      if (mounted) setState(() => _building = null);
    }
  }

  Future<void> _delete(AudioDeck a) async {
    // A deck still loaded in the player would keep pointing at a deleted file.
    final player = ref.read(deckPlayerProvider);
    if (player.deck?.deckId == a.deckId) await player.close();
    await ref.read(audioDeckStoreProvider).delete(a.deckId);
    ref.invalidate(audioDecksProvider);
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);
    final audio = ref.watch(audioDecksProvider).value ?? const <AudioDeck>[];
    final byDeck = {for (final a in audio) a.deckId: a};
    final hero = ref.watch(heroProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(T.audioTitle)),
      body: decks.when(
        loading: () => const LoadingScene(label: T.loading),
        error: (e, _) => HeroEmptyState(
          hero: hero,
          state: 'hurt',
          title: T.loadFailed,
          subtitle: '$e',
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(T.audioIntro, style: TextStyle(color: context.hk.inkSoft)),
            const SizedBox(height: 4),
            Text(
              T.audioMnNote,
              style: TextStyle(fontSize: 12, color: context.hk.inkMute),
            ),
            const SizedBox(height: 12),
            for (final d in list) ...[
              _DeckRow(
                deck: d,
                audio: byDeck[d.id],
                building: _building == d.id ? _progress : null,
                busy: _building != null,
                onCreate: () => _create(d),
                onPlay: (a) => context.push(Routes.audioPlayer(a.deckId)),
                onShare: (a) => SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(a.path, mimeType: 'audio/mpeg')],
                    subject: a.deckName,
                  ),
                ),
                onDelete: _delete,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeckRow extends StatelessWidget {
  const _DeckRow({
    required this.deck,
    required this.audio,
    required this.building,
    required this.busy,
    required this.onCreate,
    required this.onPlay,
    required this.onShare,
    required this.onDelete,
  });

  final Deck deck;
  final AudioDeck? audio;
  final (int, int)? building;
  final bool busy;
  final VoidCallback onCreate;
  final ValueChanged<AudioDeck> onPlay;
  final ValueChanged<AudioDeck> onShare;
  final ValueChanged<AudioDeck> onDelete;

  @override
  Widget build(BuildContext context) {
    final a = audio;
    final b = building;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Icon(
              a == null ? Icons.headphones_outlined : Icons.headphones,
              color: context.hk.sealText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  if (b != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: b.$2 == 0 ? null : b.$1 / b.$2,
                    ),
                    Text(
                      T.audioBuilding(b.$1, b.$2),
                      style: TextStyle(fontSize: 12, color: context.hk.inkMute),
                    ),
                  ] else if (a != null)
                    Text(
                      T.audioSummary(
                        a.cues.length,
                        formatDuration(a.durationMs),
                      ),
                      style: TextStyle(fontSize: 12, color: context.hk.inkMute),
                    ),
                ],
              ),
            ),
            if (b == null && a == null)
              FilledButton.tonal(
                onPressed: busy ? null : onCreate,
                child: const Text(T.audioCreate),
              )
            else if (b == null && a != null) ...[
              IconButton.filled(
                tooltip: T.audioPlay,
                onPressed: () => onPlay(a),
                icon: const Icon(Icons.play_arrow),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'share' => onShare(a),
                  'rebuild' => onCreate(),
                  _ => onDelete(a),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'share',
                    child: Text(T.audioShare),
                  ),
                  PopupMenuItem(
                    value: 'rebuild',
                    enabled: !busy,
                    child: const Text(T.audioRegenerate),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(T.audioDelete),
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

/// The options sheet: speak English or not, repeats, pause length, order.
Future<AudioOptions?> showAudioOptions(BuildContext context) {
  return showModalBottomSheet<AudioOptions>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _OptionsSheet(),
  );
}

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet();

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  var _o = const AudioOptions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            T.audioOptionsTitle,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(T.audioEnglish),
            value: _o.english,
            onChanged: (v) => setState(
              () => _o = AudioOptions(
                english: v,
                repeat: _o.repeat,
                pauseMs: _o.pauseMs,
                shuffle: _o.shuffle,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(T.audioShuffle),
            value: _o.shuffle,
            onChanged: (v) => setState(
              () => _o = AudioOptions(
                english: _o.english,
                repeat: _o.repeat,
                pauseMs: _o.pauseMs,
                shuffle: v,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(T.audioRepeat),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final n in [1, 2, 3])
                ButtonSegment(value: n, label: Text(T.audioRepeatN(n))),
            ],
            selected: {_o.repeat},
            onSelectionChanged: (s) => setState(
              () => _o = AudioOptions(
                english: _o.english,
                repeat: s.single,
                pauseMs: _o.pauseMs,
                shuffle: _o.shuffle,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(T.audioPause),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final ms in [1000, 1500, 3000])
                ButtonSegment(value: ms, label: Text(T.audioPauseS(ms / 1000))),
            ],
            selected: {_o.pauseMs},
            onSelectionChanged: (s) => setState(
              () => _o = AudioOptions(
                english: _o.english,
                repeat: _o.repeat,
                pauseMs: s.single,
                shuffle: _o.shuffle,
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_o),
            icon: const Icon(Icons.graphic_eq),
            label: const Text(T.audioCreate),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// The player: the word being spoken, large, with its reading and meanings —
/// the Mongolian included, since it can't be spoken — and word-by-word
/// skipping.
class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key, required this.deckId});
  final String deckId;

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  AudioDeck? _deck;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final decks = await ref.read(audioDeckStoreProvider).list();
      final deck = decks.where((d) => d.deckId == widget.deckId).firstOrNull;
      if (deck == null || !File(deck.path).existsSync()) {
        throw Exception(T.loadFailed);
      }
      final player = ref.read(deckPlayerProvider);
      await player.open(deck);
      if (!mounted) return;
      setState(() => _deck = deck);
      await player.play();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hero = ref.watch(heroProvider);
    final deck = _deck;
    final player = ref.watch(deckPlayerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(deck?.deckName ?? T.audioTitle),
        actions: [
          // For a walk with the screen locked: the phone's music app plays
          // the MP3 in the background with its own lock-screen controls.
          if (deck != null)
            IconButton(
              tooltip: T.audioOpenInMusic,
              icon: const Icon(Icons.open_in_new),
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: [XFile(deck.path, mimeType: 'audio/mpeg')], subject: deck.deckName),
              ),
            ),
        ],
      ),
      body: _error != null
          ? HeroEmptyState(
              hero: hero,
              state: 'hurt',
              title: T.loadFailed,
              subtitle: _error,
            )
          : deck == null
          ? const LoadingScene(label: T.loading)
          : StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? player.position;
                final cue = deck.cues.isEmpty
                    ? null
                    : deck.cues[deck.cueAt(pos.inMilliseconds)];
                final index = deck.cueAt(pos.inMilliseconds);
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      children: [
                        Text(
                          '${index + 1} / ${deck.cues.length}',
                          style: TextStyle(color: context.hk.inkMute),
                        ),
                        Expanded(
                          child: Center(
                            child: cue == null
                                ? const SizedBox()
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          cue.term,
                                          style: const TextStyle(
                                            fontSize: 56,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (cue.reading != null &&
                                          cue.reading != cue.term)
                                        Text(
                                          cue.reading!,
                                          style: TextStyle(
                                            fontSize: 22,
                                            color: context.hk.inkSoft,
                                          ),
                                        ),
                                      const SizedBox(height: 16),
                                      if (cue.meaningMn?.isNotEmpty ?? false)
                                        Text(
                                          cue.meaningMn!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      if (cue.meaning?.isNotEmpty ?? false)
                                        Text(
                                          cue.meaning!,
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: context.hk.inkMute,
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                        Slider(
                          value: pos.inMilliseconds
                              .clamp(0, deck.durationMs)
                              .toDouble(),
                          max: deck.durationMs.toDouble(),
                          onChanged: (v) =>
                              player.seek(Duration(milliseconds: v.round())),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(pos.inMilliseconds),
                              style: TextStyle(color: context.hk.inkMute),
                            ),
                            Text(
                              formatDuration(deck.durationMs),
                              style: TextStyle(color: context.hk.inkMute),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<bool>(
                          stream: player.playingStream,
                          builder: (context, p) {
                            final playing = p.data ?? player.playing;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  onPressed: () => player.skipWord(-1),
                                  icon: const Icon(Icons.skip_previous),
                                  iconSize: 34,
                                ),
                                IconButton(
                                  onPressed: player.rewind,
                                  icon: const Icon(Icons.replay_10),
                                  iconSize: 30,
                                ),
                                IconButton.filled(
                                  onPressed: playing
                                      ? player.pause
                                      : player.play,
                                  icon: Icon(
                                    playing ? Icons.pause : Icons.play_arrow,
                                  ),
                                  iconSize: 44,
                                  style: IconButton.styleFrom(
                                    backgroundColor: context.hk.seal,
                                  ),
                                ),
                                IconButton(
                                  onPressed: player.fastForward,
                                  icon: const Icon(Icons.forward_10),
                                  iconSize: 30,
                                ),
                                IconButton(
                                  onPressed: () => player.skipWord(1),
                                  icon: const Icon(Icons.skip_next),
                                  iconSize: 34,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
