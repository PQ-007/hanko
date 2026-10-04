import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/audio.dart';
import '../../core/offline_review.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/queue_card.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../decks/word_actions.dart' show speakWord;

const _uuid = Uuid();

/// One answered card, kept so it can be undone. The log id is generated here on
/// the device: review_card() treats it as an idempotency key, so an answer
/// retried after a dropped connection is applied exactly once instead of
/// double-counting the review and inflating the streak.
class _Answered {
  const _Answered(this.logId, this.card, this.requeued);
  final String logId;
  final QueueCard card;
  final bool requeued;
}

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.deckId, this.deckName});

  final String? deckId;
  final String? deckName;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<QueueCard>? _queue;
  bool _revealed = false;
  int _reviewed = 0;
  final List<_Answered> _history = [];
  String? _error;
  bool _sending = false;

  /// True when the queue came from the local cache rather than the server, and
  ////or answers are being written to the outbox. Surfaced in the UI: a user who
  /// reviews forty cards on a train deserves to know they haven't synced yet.
  bool _offline = false;
  int _queuedAnswers = 0;

  /// When the current card was first shown, so each answer can report how long
  /// it took. review_log.duration_ms is what battle mode later scales damage
  /// against, and it can only be measured here, at answer time.
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Anything queued from a previous offline session goes out first, so the
      // queue we then fetch already reflects those answers.
      final offline = ref.read(offlineReviewProvider);
      await offline.flush();

      final result = await offline.queue(deckId: widget.deckId);
      final queue = result.cards;
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _offline = result.fromCache;
        _shownAt = DateTime.now();
      });

      // Pull the session's clips to disk in the background. Unawaited on
      // purpose: the first card is already on screen and answerable, and a slow
      // connection must not hold up the review.
      unawaited(ref.read(audioProvider).precache(
            queue.map((c) => (wordId: c.wordId, audioPath: c.audioPath)),
          ));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  QueueCard? get _card =>
      (_queue != null && _queue!.isNotEmpty) ? _queue!.first : null;

  Future<void> _rate(String rating) async {
    final card = _card;
    if (card == null || _sending) return;

    final logId = _uuid.v4();
    final durationMs = _shownAt == null
        ? null
        : DateTime.now().difference(_shownAt!).inMilliseconds;

    // Move on immediately — the answer is committed server-side in one
    // transaction, so there is nothing to flush later or lose on navigation.
    setState(() {
      _sending = true;
      _error = null;
      _revealed = false;
      _reviewed += 1;
      _queue = _queue!.sublist(1);
      _shownAt = DateTime.now();
    });

    // Returns null when the send failed and the answer went to the outbox
    // instead — no error state, because nothing was lost and the user has no
    // action to take.
    final updated = await ref.read(offlineReviewProvider).answer(
          cardId: card.cardId,
          rating: rating,
          logId: logId,
          durationMs: durationMs,
        );

    if (!mounted) return;

    if (updated == null) {
      // Queued offline. Predict the re-queue locally from the same rules the
      // server uses: an 'again' always returns within the session, and a card
      // that hasn't graduated stays in learning.
      final stillLearning = rating == 'again' ||
          card.state == 'new' ||
          card.state == 'learning' ||
          card.state == 'relearning';
      setState(() {
        _offline = true;
        _queuedAnswers += 1;
        _history.add(_Answered(logId, card, stillLearning));
        if (stillLearning) _queue = [..._queue!, card];
        _sending = false;
      });
      return;
    }

    // A card still inside the learning or relearning steps is due again in
    // minutes, so it comes back before the session ends — that is the whole
    // point of the steps. Anything that graduated is gone until its day.
    final state = updated['state'] as String?;
    final requeued = state == 'learning' || state == 'relearning';

    setState(() {
      _history.add(_Answered(logId, card, requeued));
      if (requeued) {
        _queue = [
          ..._queue!,
          card.copyWith(
            state: state,
            learningStep: (updated['learning_step'] as num?)?.toInt(),
            intervalDays: (updated['interval_days'] as num?)?.toInt(),
            repetitions: (updated['repetitions'] as num?)?.toInt(),
            easeFactor: (updated['ease_factor'] as num?)?.toDouble(),
          ),
        ];
      }
      _sending = false;
    });
  }

  Future<void> _undo() async {
    if (_history.isEmpty || _sending) return;
    final last = _history.removeLast();

    setState(() {
      _sending = true;
      _error = null;
      _revealed = true; // you were looking at the answer when you mis-tapped
      _reviewed = _reviewed > 0 ? _reviewed - 1 : 0;
    });

    try {
      // Null means the answer was still in the outbox and has just been
      // dropped: the card never changed server-side, so the pre-answer copy we
      // already hold is the correct state to restore.
      final restored = await ref.read(offlineReviewProvider).undo(last.logId);
      if (!mounted) return;
      setState(() {
        if (restored == null && _queuedAnswers > 0) _queuedAnswers -= 1;
        final rest = _queue!.where((c) => c.cardId != last.card.cardId).toList();
        _queue = [
          restored == null
              ? last.card
              : last.card.copyWith(
                  state: restored['state'] as String?,
                  learningStep: (restored['learning_step'] as num?)?.toInt(),
                  intervalDays: (restored['interval_days'] as num?)?.toInt(),
                  repetitions: (restored['repetitions'] as num?)?.toInt(),
                  easeFactor: (restored['ease_factor'] as num?)?.toDouble(),
                ),
          ...rest,
        ];
        _shownAt = DateTime.now();
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = _card;

    if (_queue == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deckName ?? T.practice)),
        body: _error == null
            ? const LoadingScene(label: T.loading)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('${T.loadFailed}:\n$_error'),
                ),
              ),
      );
    }

    if (card == null) {
      final hero = ref.watch(heroProvider);
      return Scaffold(
        appBar: AppBar(title: Text(widget.deckName ?? T.practice)),
        body: HeroEmptyState(
          hero: hero,
          // A finished session gets the hero's heaviest swing; an empty queue
          // gets them resting.
          state: _reviewed > 0 ? 'attack01' : 'idle',
          title: _reviewed > 0 ? T.sessionComplete : T.noWordsDue,
          subtitle: _reviewed > 0 ? T.sessionCompleteDesc(_reviewed) : null,
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(T.back),
          ),
        ),
      );
    }

    final remaining = _queue!.length;
    final total = _reviewed + remaining;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deckName ?? 'Давтах'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Сүүлийн хариултыг буцаах',
            onPressed: _history.isEmpty || _sending ? null : _undo,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : _reviewed / total,
            minHeight: 4,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text(
                'Хадгалж чадсангүй: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 12),
              ),
            ),
          if (_offline)
            Container(
              width: double.infinity,
              color: context.hk.warnBg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 16, color: context.hk.warnFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _queuedAnswers > 0
                          ? 'Офлайн — $_queuedAnswers хариулт хадгалагдсан, дараа илгээнэ'
                          : 'Офлайн — хадгалсан жагсаалтаар давтаж байна',
                      style: TextStyle(
                          color: context.hk.warnFg, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _revealed = true),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        card.term,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_revealed) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (card.reading != null &&
                                card.reading!.isNotEmpty &&
                                card.reading != card.term)
                              Text(
                                card.reading!,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(color: context.hk.inkMute),
                              ),
                            // Always available: the recorded clip when there is
                            // one (cached, so it works offline), otherwise the
                            // phone's own Japanese voice.
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.volume_up_outlined),
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                if (card.audioPath != null && card.audioPath!.isNotEmpty) {
                                  ref.read(audioProvider).play(card.wordId, card.audioPath);
                                } else {
                                  speakWord(context, ref, reading: card.reading, term: card.term);
                                }
                              },
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(),
                        ),
                        if (card.meaningMn != null && card.meaningMn!.isNotEmpty)
                          Text(
                            card.meaningMn!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                        if (card.meaning != null && card.meaning!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            card.meaning!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: context.hk.inkMute),
                          ),
                        ],
                      ] else ...[
                        const SizedBox(height: 32),
                        Text(
                          'Хариулт харах',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: context.hk.inkMute),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              // Lifted into thumb reach rather than pinned to the bottom edge.
              padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + thumbZoneLift(context)),
              child: _revealed
                  ? RatingButtonRow(enabled: !_sending, onRate: _rate)
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => setState(() => _revealed = true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        child: const Text(T.showAnswer),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared by every screen that grades a card. Deliberately no interval preview:
/// the web removed it because the scheduled gap read as a forgetting date
/// rather than "when I'll ask again", and mobile's copy was a stale SM-2
/// formula besides — the server has scheduled with FSRS since 0021.
class RatingButtonRow extends StatelessWidget {
  const RatingButtonRow({super.key, required this.enabled, required this.onRate});
  final bool enabled;
  final ValueChanged<String> onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final r in const ['again', 'hard', 'good', 'easy'])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _RatingButton(rating: r, enabled: enabled, onTap: () => onRate(r)),
            ),
          ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.enabled,
    required this.onTap,
  });

  final String rating;
  final bool enabled;
  final VoidCallback onTap;

  static const _labels = {
    'again': T.again,
    'hard': T.hard,
    'good': T.good,
    'easy': T.easy,
  };

  @override
  Widget build(BuildContext context) {
    final color = context.hk.rating(rating);
    final primary = rating == 'good';
    return primary
        ? FilledButton(
            onPressed: enabled ? onTap : null,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
            ),
            child: Text(_labels[rating]!,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          )
        : OutlinedButton(
            onPressed: enabled ? onTap : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.4)),
              backgroundColor: color.withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
            ),
            child: Text(_labels[rating]!,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          );
  }
}
