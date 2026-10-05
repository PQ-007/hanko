import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/local_db.dart';
import 'package:mobile/core/offline_review.dart';
import 'package:mobile/core/repository.dart';
import 'package:mobile/features/battle/battle_controller.dart';
import 'package:mobile/features/battle/question_kinds.dart';
import 'package:mobile/features/battle/rules.dart';
import 'package:mobile/features/battle/sprites.dart';
import 'package:mobile/models/queue_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records every review_card() call; can be told to fail like a dead network.
class FakeRepo extends Repository {
  // No auto-refresh: the dummy client would otherwise leave a periodic
  // session-refresh timer running past the end of every test.
  FakeRepo(this.cards)
      : super(SupabaseClient('http://localhost', 'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final List<QueueCard> cards;
  final calls = <Map<String, Object?>>[];
  final undone = <String>[];
  bool offline = false;
  String nextState = 'review';
  int queueFetches = 0, practiceFetches = 0;

  @override
  Future<List<QueueCard>> reviewQueue({String? deckId, int limit = 60}) async {
    queueFetches++;
    if (offline) throw Exception('offline');
    return cards;
  }

  @override
  Future<List<QueueCard>> practiceCards({String? deckId, int limit = 60}) async {
    practiceFetches++;
    return cards;
  }

  @override
  Future<List<QuizWordRow>> quizWords() async => [
        for (var i = 0; i < 6; i++)
          (id: 'w$i', term: '語$i', reading: 'ご$i', meaning: 'm$i', meaningMn: 'мн$i'),
      ];

  @override
  Future<Map<String, dynamic>> reviewCard({
    required String cardId,
    required String rating,
    required String logId,
    int? durationMs,
    String source = 'review',
  }) async {
    if (offline) throw Exception('offline');
    calls.add({'card': cardId, 'rating': rating, 'source': source, 'log': logId});
    return {'state': nextState, 'learning_step': 0, 'interval_days': 1, 'repetitions': 1, 'ease_factor': 2.5};
  }

  @override
  Future<Map<String, dynamic>> undoReview(String logId) async {
    undone.add(logId);
    return {'state': 'review', 'learning_step': 0, 'interval_days': 3, 'repetitions': 2, 'ease_factor': 2.5};
  }
}

QueueCard card(int i, {String state = 'review'}) => QueueCard(
      cardId: 'c$i',
      wordId: 'w$i',
      deckId: 'd',
      template: 'recognition',
      state: state,
      learningStep: 0,
      dueAt: DateTime(2026),
      intervalDays: 3,
      repetitions: 2,
      easeFactor: 2.5,
      term: '語$i',
      reading: 'ご$i',
      meaningMn: 'мн$i',
    );

/// Builds a controller in a fake-time zone and finishes loading.
BattleController make(
  FakeAsync async,
  FakeRepo repo, {
  bool free = false,
  Set<QuestionKind> kinds = const {QuestionKind.meaning},
  bool canWrite = false,
}) {
  final db = LocalDb.forTesting(NativeDatabase.memory());
  // 0.99: never crit, never evade, so damage is exactly the base number.
  final clock = async.getClock(DateTime(2026));
  final c = BattleController(
    offline: OfflineReview(repo, db),
    repo: repo,
    hero: 'knight',
    free: free,
    rand: () => 0.99,
    bag: MonsterBag(random: () => 0.5),
    now: () => clock.now().millisecondsSinceEpoch,
    // Pinned to the web's question kind unless a test is about the others,
    // so the damage and timing expectations stay exact.
    kinds: kinds,
    writingReady: () async => canWrite,
  );
  c.load();
  async.flushMicrotasks();
  return c;
}

void pickCorrect(BattleController c) => c.pick(c.quiz!.firstWhere((o) => o.correct));
void pickWrong(BattleController c) => c.pick(c.quiz!.firstWhere((o) => !o.correct));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fast correct answer hits hard but is scheduled as good, labelled quiz', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo);
      expect(c.card!.cardId, 'c1');
      pickCorrect(c); // instant: the "easy" speed tier
      async.flushMicrotasks();
      expect(repo.calls.single['rating'], 'good', reason: 'the scheduler is never told easy');
      expect(repo.calls.single['source'], 'quiz');
      expect(c.state.monsterHp, monsterMaxHp - 16, reason: 'easy tier: 12 x 1.3');
      expect(c.card!.cardId, 'c2');
      c.dispose();
    });
  });

  test('a wrong answer costs the player, schedules "again", and breaks the streak', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2), card(3)]);
      final c = make(async, repo);
      pickCorrect(c);
      async.flushMicrotasks();
      pickWrong(c);
      async.flushMicrotasks();
      expect(repo.calls.last['rating'], 'again');
      expect(c.state.playerHp, playerMaxHp - 15);
      expect(c.state.streak, 0);
      c.dispose();
    });
  });

  test('free practice reads practice_cards and answers as drill', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo, free: true);
      expect(repo.practiceFetches, 1);
      expect(repo.queueFetches, 0);
      pickCorrect(c);
      async.flushMicrotasks();
      expect(repo.calls.single['source'], 'drill');
      c.dispose();
    });
  });

  test('the clock running out is one honest miss, flagged as a timeout', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo);
      async.elapse(const Duration(milliseconds: 9900));
      expect(repo.calls, isEmpty, reason: 'still answerable at 9.9s');
      async.elapse(const Duration(milliseconds: 300));
      expect(repo.calls, hasLength(1), reason: 'resolved exactly once');
      expect(repo.calls.single['rating'], 'again');
      expect(c.events.single.timedOut, isTrue);
      expect(c.flag, BattleFlag.timeout);
      expect(c.state.playerHp, playerMaxHp - 15);
      // The next question started at 10.0s; 200ms of the window ran on it.
      expect(c.remainingMs, questionTimeLimitMs - 200, reason: 'next question got a fresh clock');
      c.dispose();
    });
  });

  test('pause stops the clock; resuming picks up where it left off', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo);
      async.elapse(const Duration(seconds: 4));
      c.togglePause();
      async.elapse(const Duration(seconds: 30));
      expect(repo.calls, isEmpty, reason: 'no timeout while paused');
      c.togglePause();
      async.elapse(const Duration(milliseconds: 5900));
      expect(repo.calls, isEmpty, reason: '4s + 5.9s is still under 10s');
      async.elapse(const Duration(milliseconds: 300));
      expect(repo.calls.single['rating'], 'again');
      c.dispose();
    });
  });

  test('the speed tiers grade a correct answer by real elapsed time', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2), card(3)]);
      final c = make(async, repo);
      async.elapse(const Duration(seconds: 5)); // middle third: good
      pickCorrect(c);
      async.flushMicrotasks();
      expect(c.events.last.damage, 12);
      async.elapse(const Duration(seconds: 8)); // last third: hard
      pickCorrect(c);
      async.flushMicrotasks();
      expect(c.events.last.damage, 8);
      expect(repo.calls.map((x) => x['rating']), ['good', 'hard']);
      c.dispose();
    });
  });

  test('killing a monster spawns the next one in place, keeping player HP', () {
    fakeAsync((async) {
      final repo = FakeRepo([for (var i = 0; i < 12; i++) card(i)]);
      final c = make(async, repo);
      final first = c.monster;
      pickWrong(c); // the player carries this damage into the next fight
      async.flushMicrotasks();
      // 16 per instant correct answer: 7 hits bring 100 HP to 0.
      for (var i = 0; i < 7; i++) {
        pickCorrect(c);
        async.flushMicrotasks();
      }
      expect(c.state.monsterDefeated, isTrue);
      expect(c.flag, BattleFlag.victory);
      async.elapse(const Duration(milliseconds: 1300));
      expect(c.defeatedMonsters, [first]);
      expect(c.monster, isNot(first));
      expect(c.state.monsterHp, monsterMaxHp, reason: 'a fresh monster starts full');
      expect(c.state.playerHp, playerMaxHp - 15, reason: 'player HP is not refilled');
      expect(c.outcome, BattleOutcome.ongoing);
      c.dispose();
    });
  });

  test('a card still in its learning steps comes back this session', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1, state: 'new')])..nextState = 'learning';
      final c = make(async, repo);
      pickWrong(c);
      async.flushMicrotasks();
      expect(c.card?.cardId, 'c1', reason: 'requeued, not the end of the run');
      expect(c.outcome, BattleOutcome.ongoing);
      c.dispose();
    });
  });

  test('answering the last card ends the run as cleared', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1)]);
      final c = make(async, repo);
      pickCorrect(c);
      async.flushMicrotasks();
      expect(c.outcome, BattleOutcome.cleared);
      expect(c.reviewedCount, 1);
      c.dispose();
    });
  });

  test('undo drops the blow and puts the card back at the front', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo);
      pickCorrect(c);
      async.flushMicrotasks();
      c.undo();
      async.flushMicrotasks();
      expect(c.events, isEmpty);
      expect(c.state.monsterHp, monsterMaxHp);
      expect(c.card!.cardId, 'c1');
      expect(repo.undone, [repo.calls.single['log']]);
      c.dispose();
    });
  });

  test('offline, the answer is queued with its quiz label and the fight goes on', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final db = LocalDb.forTesting(NativeDatabase.memory());
      final offline = OfflineReview(repo, db);
      final c = BattleController(
        offline: offline,
        repo: repo,
        hero: 'knight',
        rand: () => 0.99,
        bag: MonsterBag(random: () => 0.5),
        kinds: const {QuestionKind.meaning},
        writingReady: () async => false,
      )..load();
      async.flushMicrotasks();
      repo.offline = true;
      pickCorrect(c);
      async.flushMicrotasks();
      expect(c.queuedOffline, 1);
      expect(c.state.monsterHp, lessThan(monsterMaxHp));
      late List<PendingAnswer> pending;
      db.pending().then((p) => pending = p);
      async.flushMicrotasks();
      expect(pending.single.source, 'quiz');
      expect(pending.single.rating, 'good');
      c.dispose();
    });
  });

  test('without the handwriting model, writing is never asked', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1)]);
      final c = make(async, repo, kinds: {QuestionKind.write, QuestionKind.meaning});
      expect(c.canWrite, isFalse);
      expect(c.kind, QuestionKind.meaning);
      c.dispose();
    });
  });

  test('writing: one kanji at a time, then the blow lands half again as hard', () {
    fakeAsync((async) {
      // '語1' has one kanji; the first card is a two-kanji word.
      final repo = FakeRepo([
        QueueCard(
          cardId: 'c1', wordId: 'w1', deckId: 'd', template: 'recognition', state: 'review', learningStep: 0,
          dueAt: DateTime(2026), intervalDays: 3, repetitions: 2, easeFactor: 2.5,
          term: '連帯', reading: 'れんたい', meaningMn: 'эв нэгдэл',
        ),
        card(2),
      ]);
      final c = make(async, repo, kinds: {QuestionKind.write}, canWrite: true);
      expect(c.kind, QuestionKind.write);
      expect(c.timeLimitMs, 2 * writeMsPerKanji);
      expect(c.remainingMs, 2 * writeMsPerKanji);
      c.writeResult(true);
      expect(c.writeSlot, 1, reason: 'first kanji done, second next');
      expect(repo.calls, isEmpty, reason: 'not answered until the whole word is written');
      c.writeResult(true);
      async.flushMicrotasks();
      // Instant: easy tier 16 damage, x1.5 for writing = 24.
      expect(c.events.single.damage, 24);
      expect(c.state.monsterHp, monsterMaxHp - 24);
      expect(repo.calls.single['rating'], 'good', reason: 'still never easy');
      c.dispose();
    });
  });

  test('a wrong kanji ends the writing question as a miss', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo, kinds: {QuestionKind.write}, canWrite: true);
      c.writeResult(false);
      async.flushMicrotasks();
      expect(repo.calls.single['rating'], 'again');
      expect(c.state.playerHp, playerMaxHp - 15);
      c.dispose();
    });
  });

  test('a writing question gets its own, longer clock', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo, kinds: {QuestionKind.write}, canWrite: true);
      async.elapse(const Duration(seconds: 11));
      expect(repo.calls, isEmpty, reason: 'a choice question would have timed out by now');
      async.elapse(const Duration(milliseconds: 1200));
      expect(repo.calls.single['rating'], 'again');
      c.dispose();
    });
  });

  test('a correction on screen stops the clock; continuing lands the miss', () {
    fakeAsync((async) {
      final repo = FakeRepo([card(1), card(2)]);
      final c = make(async, repo, kinds: {QuestionKind.write}, canWrite: true);
      async.elapse(const Duration(seconds: 5));
      c.holdForCorrection();
      async.elapse(const Duration(seconds: 60));
      expect(repo.calls, isEmpty, reason: 'no timeout while the correction is shown');
      c.writeResult(false);
      async.flushMicrotasks();
      expect(repo.calls.single['rating'], 'again');
      expect(c.held, isFalse);
      expect(c.remainingMs, writeMsPerKanji, reason: 'the next question starts with a full clock');
      c.dispose();
    });
  });
}
