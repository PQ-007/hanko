import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/offline_review.dart';
import '../../core/repository.dart';
import '../../models/queue_card.dart';
import 'rules.dart';
import 'sprites.dart';

const _uuid = Uuid();

// Timings from BattleArena.tsx, so the fight has the same rhythm on both apps.
const _flagHoldMs = 900;
const _monsterSpawnDelayMs = 1200;
const _rangedSpawnDelayMs = 700;
const projectileFlightMs = 260;
const _projectileLaunchMs = oneShotMs;
const _tickMs = 100;

enum BattleFlag { crit, evaded, armor, timeout, victory }

class LastAnswer {
  const LastAnswer(this.term, this.reading, this.correct);
  final String term;
  final String? reading;
  final bool correct;
}

class DamagePopup {
  const DamagePopup(this.id, this.amount, {required this.onMonster, required this.crit});
  final int id;
  final int amount;
  final bool onMonster;
  final bool crit;
}

class Shot {
  const Shot(this.id, this.slug, this.pose, this.frames, {required this.towardRight});
  final int id;
  final String slug;
  final String pose;
  final int frames;
  final bool towardRight;
}

/// A pausable stopwatch over an injectable time source, so tests can drive the
/// question clock with fake time (a dart:core Stopwatch can't be faked).
class _QuestionClock {
  _QuestionClock(this._now);
  final int Function() _now;
  int _banked = 0;
  int? _startedAt;

  int get elapsedMilliseconds => _banked + (_startedAt == null ? 0 : _now() - _startedAt!);

  void start() => _startedAt ??= _now();

  void stop() {
    if (_startedAt == null) return;
    _banked += _now() - _startedAt!;
    _startedAt = null;
  }

  void reset() {
    _banked = 0;
    if (_startedAt != null) _startedAt = _now();
  }
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

class _Answered {
  const _Answered(this.logId, this.card, this.requeued);
  final String logId;
  final QueueCard card;
  final bool requeued;
}

/// Monster Hunt: a skin over a real review session. Port of the web's
/// BattleArena.tsx (the fight) and usePracticeSession.ts (the session), with
/// the answers going through mobile's offline outbox.
///
/// Due mode reads `review_queue()` and answers as 'quiz' — real scheduling,
/// labelled (0018). Free mode reads `practice_cards()` and answers as 'drill' —
/// logged, never scheduled. Either way the scheduler is never told 'easy'
/// (rules.dart `scheduleRating`).
///
/// HP is a pure fold over [events] (rules.dart `deriveBattleState`), and each
/// answer's randomness is rolled exactly once when it happens, so undo is just
/// dropping the last event.
class BattleController extends ChangeNotifier {
  BattleController({
    required this.offline,
    required this.repo,
    required this.hero,
    this.deckId,
    this.free = false,
    this.rand = defaultRand,
    MonsterBag? bag,
    int Function() now = _wallClockMs,
  })  : bag = bag ?? monsterBag,
        _clock = _QuestionClock(now) {
    monster = this.bag.pick(exclude: hero);
  }

  final OfflineReview offline;
  final Repository repo;
  final Rand rand;
  final MonsterBag bag;

  final String hero;
  final String? deckId;
  final bool free;

  String get _source => free ? 'drill' : 'quiz';

  // ---- Session --------------------------------------------------------------
  List<QueueCard>? queue;
  List<QuizWord>? words;
  String? loadError;
  bool fromCache = false;
  int queuedOffline = 0;
  bool saveError = false;
  int reviewedCount = 0;
  int _pendingAnswers = 0;
  final _history = <_Answered>[];

  QueueCard? get card => (queue?.isNotEmpty ?? false) ? queue!.first : null;

  // ---- Fight ----------------------------------------------------------------
  final events = <BattleEvent>[];
  int monsterStartIndex = 0;
  late String monster;
  final defeatedMonsters = <String>[];
  List<QuizOption>? quiz;

  String playerPose = 'idle';
  String monsterPose = 'idle';

  /// Bumped on every pose change so a repeated pose (two crits in a row)
  /// replays from frame 0 instead of looking like one still-running clip.
  int playerPoseKey = 0;
  int monsterPoseKey = 0;

  BattleFlag? flag;
  LastAnswer? lastAnswer;
  DamagePopup? popup;
  int shakeId = 0;
  bool paused = false;
  bool impactPending = false;
  Shot? shot;

  // ---- Clock ----------------------------------------------------------------
  final _QuestionClock _clock;
  int remainingMs = questionTimeLimitMs;
  bool _answered = false;
  String? _questionKey;

  Timer? _tick;
  Timer? _flagTimer;
  Timer? _impactTimer;
  Timer? _launchTimer;
  Timer? _spawnTimer;
  int _postImpactSpawnMs = _monsterSpawnDelayMs;
  bool _disposed = false;

  BattleState get state => deriveBattleState(events, monsterStartIndex);

  BattleOutcome get outcome {
    // The pending counter tells "queue is empty" apart from "queue is briefly
    // empty while a still-learning card is on its way back" — without it the
    // result screen would flash after answering the last card with "again".
    final queueEmpty = queue != null && card == null && events.isNotEmpty && _pendingAnswers == 0;
    return battleOutcome(state, queueIsEmpty: queueEmpty);
  }

  bool get notEnoughWords => words != null && words!.length < minWordsForBattle;

  /// Nobody falls over until the shot that killed them has landed.
  String get playerDisplayPose =>
      state.playerDefeated && !impactPending ? 'death' : playerPose;
  String get monsterDisplayPose =>
      state.monsterDefeated && !impactPending ? 'death' : monsterPose;

  bool get canUndo => events.isNotEmpty && _history.isNotEmpty;

  Future<void> load() async {
    try {
      // Anything answered offline last time goes out first, so the queue
      // fetched next already reflects it.
      await offline.flush();
    } catch (_) {}
    try {
      final rows = await offline.quizWords();
      words = [
        for (final w in rows)
          QuizWord(id: w.id, term: w.term, reading: w.reading, meaning: w.meaning, meaningMn: w.meaningMn),
      ];
      if (free) {
        queue = await repo.practiceCards(deckId: deckId);
      } else {
        final result = await offline.queue(deckId: deckId);
        queue = result.cards;
        fromCache = result.fromCache;
      }
    } catch (e) {
      // Surfaced, not swallowed: a failed load must not look like "nothing due".
      loadError = '$e';
      queue ??= const [];
      words ??= const [];
    }
    _afterChange();
  }

  // ---- Answering ------------------------------------------------------------

  void pick(QuizOption option) {
    if (card == null || quiz == null || _answered || paused || outcome != BattleOutcome.ongoing) {
      return;
    }
    _answered = true;
    _resolve(option.correct ? ratingForElapsed(_clock.elapsedMilliseconds) : 'again', timedOut: false);
  }

  /// Shared by a pick and an expired clock. [speed] grades the answer for the
  /// fight; what reaches the scheduler is capped (never 'easy').
  void _resolve(String speed, {required bool timedOut}) {
    final answeredCard = card;
    final rating = scheduleRating(speed);
    final before = state;
    final event = rollEvent(
      speed,
      streak: before.streak,
      armorCharges: before.armorCharges,
      timedOut: timedOut,
      rand: rand,
    );
    events.add(event);
    final after = state;
    final killed = after.monsterDefeated;

    if (answeredCard != null) {
      lastAnswer = LastAnswer(answeredCard.term, answeredCard.reading, event.correct);
    }

    if (event.correct) {
      // The swing escalates with the streak; a crit always lands the heaviest.
      final pose = attackPose(hero, event.crit ? maxAttackTier : streakTier(after.streak));
      _setPlayerPose(pose);
      flag = killed ? BattleFlag.victory : (event.crit ? BattleFlag.crit : null);
      final frames = projectileFor(hero, pose);
      _postImpactSpawnMs = frames != null ? _rangedSpawnDelayMs : _monsterSpawnDelayMs;
      if (frames != null) _launch(hero, pose, frames, towardRight: true);
      _onImpact(frames != null, () {
        _setMonsterPose('hurt');
        popup = DamagePopup(DateTime.now().microsecondsSinceEpoch, event.damage,
            onMonster: true, crit: event.crit);
        if (killed) {
          _buzzVictory();
        } else if (event.crit) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
      });
    } else {
      _setMonsterPose('attack01');
      flag = timedOut
          ? BattleFlag.timeout
          : event.armorConsumed
              ? BattleFlag.armor
              : event.evaded
                  ? BattleFlag.evaded
                  : null;
      final frames = projectileFor(monster, 'attack01');
      if (frames != null) _launch(monster, 'attack01', frames, towardRight: false);
      _onImpact(frames != null, () {
        _setPlayerPose(event.armorConsumed || event.evaded ? 'idle' : 'hurt');
        if (event.damage > 0) {
          popup = DamagePopup(DateTime.now().microsecondsSinceEpoch, event.damage,
              onMonster: false, crit: false);
          shakeId++;
          HapticFeedback.heavyImpact();
        } else {
          // A save costs nothing, so it gets a light tick, not a shake.
          HapticFeedback.selectionClick();
        }
      });
    }

    unawaited(_rate(rating));

    _flagTimer?.cancel();
    _flagTimer = Timer(Duration(milliseconds: killed ? _monsterSpawnDelayMs : _flagHoldMs), () {
      flag = null;
      lastAnswer = null;
      popup = null;
      shot = null;
      _notify();
    });

    _afterChange();
  }

  /// usePracticeSession's rate(): optimistic advance, then the server (or the
  /// outbox). A card still in its learning steps comes back this session.
  Future<void> _rate(String rating) async {
    final current = card;
    if (current == null) return;
    final logId = _uuid.v4();
    final durationMs = _clock.elapsedMilliseconds;

    queue = queue!.sublist(1);
    reviewedCount++;
    _pendingAnswers++;
    saveError = false;

    Map<String, dynamic>? updated;
    var queued = false;
    try {
      updated = await offline.answer(
        cardId: current.cardId,
        rating: rating,
        logId: logId,
        durationMs: durationMs,
        source: _source,
      );
      queued = updated == null;
    } catch (e) {
      // Not even the outbox took it: put the card back rather than lose it.
      _pendingAnswers--;
      if (_disposed) return;
      saveError = true;
      reviewedCount = max(0, reviewedCount - 1);
      queue = [current, ...queue!];
      _afterChange();
      return;
    }
    _pendingAnswers--;
    if (_disposed) return;

    final bool requeued;
    String? newState;
    if (queued) {
      // Predict the server: 'drill' never moves a card, so only cards already
      // in the steps come back; a scheduling answer also requeues new cards
      // and every 'again'.
      queuedOffline++;
      requeued = free
          ? (current.state == 'learning' || current.state == 'relearning')
          : (rating == 'again' ||
              current.state == 'new' ||
              current.state == 'learning' ||
              current.state == 'relearning');
    } else {
      newState = updated['state'] as String?;
      requeued = newState == 'learning' || newState == 'relearning';
    }

    _history.add(_Answered(logId, current, requeued));
    if (requeued) {
      queue = [
        ...queue!,
        updated == null
            ? current
            : current.copyWith(
                state: newState,
                learningStep: (updated['learning_step'] as num?)?.toInt(),
                intervalDays: (updated['interval_days'] as num?)?.toInt(),
                repetitions: (updated['repetitions'] as num?)?.toInt(),
                easeFactor: (updated['ease_factor'] as num?)?.toDouble(),
              ),
      ];
    }
    _afterChange();
  }

  Future<void> undo() async {
    if (!canUndo) return;
    _impactTimer?.cancel();
    _launchTimer?.cancel();
    impactPending = false;
    shot = null;
    events.removeLast();
    final last = _history.removeLast();
    reviewedCount = max(0, reviewedCount - 1);
    saveError = false;
    _afterChange();

    Map<String, dynamic>? restored;
    try {
      // Drops it from the outbox if it never left, else undo_review().
      restored = await offline.undo(last.logId);
    } catch (_) {
      if (_disposed) return;
      saveError = true;
      _afterChange();
      return;
    }
    if (_disposed) return;
    final rest = queue!.where((c) => c.cardId != last.card.cardId).toList();
    queue = [
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
    _afterChange();
  }

  void togglePause() {
    paused = !paused;
    _afterChange();
  }

  /// Starts the fight over after a defeat. Only the battle record resets —
  /// the reviews already answered stay answered, so the queue picks up where
  /// it left off.
  void retry() {
    for (final t in [_impactTimer, _launchTimer, _spawnTimer, _flagTimer]) {
      t?.cancel();
    }
    _spawnTimer = null;
    paused = false;
    impactPending = false;
    events.clear();
    monsterStartIndex = 0;
    monster = bag.pick(exclude: hero);
    defeatedMonsters.clear();
    _setPlayerPose('idle');
    _setMonsterPose('idle');
    flag = null;
    lastAnswer = null;
    popup = null;
    shot = null;
    _afterChange();
  }

  void playerPoseEnded() {
    if (playerPose == 'idle') return;
    playerPose = 'idle';
    _notify();
  }

  void monsterPoseEnded() {
    if (monsterPose == 'idle') return;
    monsterPose = 'idle';
    _notify();
  }

  // ---- Internals ------------------------------------------------------------

  void _setPlayerPose(String pose) {
    playerPose = pose;
    playerPoseKey++;
  }

  void _setMonsterPose(String pose) {
    monsterPose = pose;
    monsterPoseKey++;
  }

  /// Melee reacts now; a ranged hit waits for the throw and the flight. Only
  /// the reaction waits — the next question is already live.
  void _onImpact(bool ranged, VoidCallback react) {
    _impactTimer?.cancel();
    if (!ranged) {
      impactPending = false;
      react();
      return;
    }
    impactPending = true;
    _impactTimer = Timer(const Duration(milliseconds: _projectileLaunchMs + projectileFlightMs), () {
      impactPending = false;
      react();
      _afterChange();
    });
  }

  /// The projectile appears once the throw is finished, not parked at the
  /// thrower's feet during the wind-up.
  void _launch(String slug, String pose, int frames, {required bool towardRight}) {
    _launchTimer?.cancel();
    _launchTimer = Timer(const Duration(milliseconds: _projectileLaunchMs), () {
      shot = Shot(DateTime.now().microsecondsSinceEpoch, slug, pose, frames, towardRight: towardRight);
      _notify();
    });
  }

  void _buzzVictory() {
    HapticFeedback.heavyImpact();
    Timer(const Duration(milliseconds: 120), HapticFeedback.heavyImpact);
  }

  /// Re-evaluates everything that hangs off the current question and the
  /// fight's state: a new question rebuilds its options and restarts the
  /// clock, a dead monster schedules its replacement, and the clock runs only
  /// while there's an answerable question.
  void _afterChange() {
    if (_disposed) return;
    final c = card;
    // Unique per presentation, not per card: a requeued card returns with the
    // same id and must still get a fresh question and a full clock.
    final key = '${c?.cardId ?? ''}:${events.length}';
    if (key != _questionKey) {
      _questionKey = key;
      _answered = false;
      quiz = (c != null && words != null)
          ? buildQuiz(
              wordId: c.wordId,
              term: c.term,
              reading: c.reading,
              meaning: c.meaning,
              meaningMn: c.meaningMn,
              allWords: words!,
              rand: rand,
            )
          : null;
      _clock
        ..stop()
        ..reset();
      remainingMs = questionTimeLimitMs;
    }

    final s = state;
    final ongoing = outcome == BattleOutcome.ongoing;

    // A defeated monster is replaced in place; only defeat or an empty queue
    // ends the run. Held until a ranged killing blow has actually landed.
    if (s.monsterDefeated && ongoing && !impactPending) {
      _spawnTimer ??= Timer(Duration(milliseconds: _postImpactSpawnMs), _spawn);
    } else if (!s.monsterDefeated) {
      _spawnTimer?.cancel();
      _spawnTimer = null;
    }

    final running = c != null && quiz != null && ongoing && !paused;
    if (running) {
      _clock.start();
      _tick ??= Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _onTick());
    } else {
      _clock.stop();
      _tick?.cancel();
      _tick = null;
    }
    _notify();
  }

  void _onTick() {
    remainingMs = max(0, questionTimeLimitMs - _clock.elapsedMilliseconds);
    if (remainingMs <= 0 && !_answered) {
      _answered = true;
      _resolve('again', timedOut: true);
      return;
    }
    _notify();
  }

  void _spawn() {
    _spawnTimer = null;
    if (outcome != BattleOutcome.ongoing || !state.monsterDefeated) return;
    monsterStartIndex = events.length;
    defeatedMonsters.add(monster);
    monster = bag.pick(exclude: hero);
    _setPlayerPose('idle');
    _setMonsterPose('idle');
    _afterChange();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in [_tick, _flagTimer, _impactTimer, _launchTimer, _spawnTimer]) {
      t?.cancel();
    }
    super.dispose();
  }
}
