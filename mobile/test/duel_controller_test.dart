import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/repository.dart';
import 'package:mobile/features/duel/duel_controller.dart';
import 'package:mobile/features/duel/duel_rules.dart';
import 'package:mobile/features/duel/duel_shared.dart';
import 'package:mobile/features/duel/opponent.dart';
import 'package:mobile/models/queue_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeRepo extends Repository {
  FakeRepo()
    : super(SupabaseClient('http://localhost', 'k', authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final logged = <Map<String, Object?>>[];
  int practiceCalls = 0;

  @override
  Future<List<QueueCard>> practiceCards({String? deckId, int limit = 60}) async {
    practiceCalls++;
    return [
      for (var i = 0; i < 5; i++)
        QueueCard(
          cardId: 'c$i',
          wordId: 'w$i',
          deckId: 'd',
          template: 'recognition',
          state: 'review',
          learningStep: 0,
          dueAt: DateTime(2026),
          intervalDays: 3,
          repetitions: 2,
          easeFactor: 2.5,
          term: '語$i',
          reading: 'ご$i',
          meaningMn: 'мн$i',
        ),
    ];
  }

  @override
  Future<List<QuizWordRow>> quizWords() async => [
    for (var i = 0; i < 6; i++) (id: 'w$i', term: '語$i', reading: 'ご$i', meaning: 'm$i', meaningMn: 'мн$i'),
  ];

  @override
  Future<Map<String, dynamic>> reviewCard({
    required String cardId,
    required String rating,
    required String logId,
    int? durationMs,
    String source = 'review',
  }) async {
    logged.add({'card': cardId, 'rating': rating, 'source': source});
    return {};
  }
}

/// A bot that always answers in [ms], right or wrong.
class FixedBot extends OpponentDriver {
  FixedBot({this.correct = true, this.ms = 3000, this.never = false});
  final bool correct;
  final int ms;
  final bool never;
  @override
  String get name => 'bot';
  @override
  String get slug => 'skeleton';
  @override
  int? get baselineMs => 4000;
  @override
  Future<DuelAnswer?> answerFor(int roundNo, int durationMs, RoundCancel cancel) => Future.delayed(
    Duration(milliseconds: never ? durationMs : ms),
    () => never ? null : DuelAnswer(correct: correct, elapsedMs: ms),
  );
}

/// A real opponent whose app went away: no answers, and after three rounds
/// the driver reports them gone (RemoteOpponent's rule).
class VanishingOpponent extends FixedBot {
  VanishingOpponent() : super(never: true);
  int rounds = 0;
  @override
  bool get left => rounds >= 3;
  @override
  Future<DuelAnswer?> answerFor(int roundNo, int durationMs, RoundCancel cancel) {
    rounds++;
    return super.answerFor(roundNo, durationMs, cancel);
  }
}

DuelController make(FakeAsync async, FakeRepo repo, OpponentDriver bot) {
  final clock = async.getClock(DateTime(2026));
  final c = DuelController(
    repo: repo,
    opponent: bot,
    hero: 'knight',
    yourBaselineMs: 4000,
    rand: () => 0.5,
    now: () => clock.now().millisecondsSinceEpoch,
  )..load();
  async.flushMicrotasks();
  return c;
}

void answerRight(DuelController c) => c.pick(c.quiz!.firstWhere((o) => o.correct));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both answer; damage lands at round end, then the next round starts', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final c = make(async, repo, FixedBot(correct: false));
      expect(c.roundNo, 1);
      async.elapse(const Duration(milliseconds: 1000));
      answerRight(c);
      expect(c.state.theirHp, duelMaxHp, reason: 'nothing lands until the opponent has answered too');
      async.elapse(const Duration(milliseconds: 2100));
      expect(c.phase, DuelPhase.resolving);
      // 1 s answer against a 4 s baseline: ratio capped at 1.6 -> 8 x 1.6 = 13.
      expect(c.state.theirHp, duelMaxHp - 13);
      expect(c.state.yourHp, duelMaxHp, reason: 'their wrong answer deals nothing');
      async.elapse(const Duration(milliseconds: resolveHoldMs + 10));
      expect(c.roundNo, 2);
      expect(c.phase, DuelPhase.question);
      c.dispose();
    });
  });

  test('answers are logged as battle — never scheduled', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final c = make(async, repo, FixedBot());
      answerRight(c);
      async.flushMicrotasks();
      expect(repo.logged.single['source'], 'battle');
      expect(repo.logged.single['rating'], 'good');
      c.dispose();
    });
  });

  test('the clock running out is a null answer that deals nothing', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final c = make(async, repo, FixedBot(correct: true, ms: 2000));
      async.elapse(Duration(milliseconds: roundDurationMs(1) + 200));
      expect(c.timedOut, isTrue);
      expect(c.phase, DuelPhase.resolving);
      expect(c.state.theirHp, duelMaxHp);
      expect(c.state.yourHp, lessThan(duelMaxHp), reason: 'the bot still hit');
      c.dispose();
    });
  });

  test('a full match against a bot that never answers ends in a win', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final c = make(async, repo, FixedBot(never: true));
      for (var r = 0; r < duelRoundCount && c.outcome == DuelOutcome.ongoing; r++) {
        answerRight(c);
        async.elapse(Duration(milliseconds: roundDurationMs(c.roundNo) + resolveHoldMs + 50));
      }
      expect(c.outcome, DuelOutcome.won);
      expect(c.state.yourHp, duelMaxHp);
      c.dispose();
    });
  });

  test('a match where neither side ever answers ends level: a draw', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final c = make(async, repo, FixedBot(never: true));
      for (var r = 0; r < duelRoundCount; r++) {
        async.elapse(Duration(milliseconds: roundDurationMs(c.roundNo) + resolveHoldMs + 50));
      }
      expect(c.state.roundsPlayed, duelRoundCount);
      expect(c.outcome, DuelOutcome.draw);
      c.dispose();
    });
  });

  test('leaving mid-round cancels the wait cleanly', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final c = make(async, repo, FixedBot(ms: 5000));
      async.elapse(const Duration(milliseconds: 500));
      c.dispose();
      async.elapse(const Duration(seconds: 30));
      // No exception, no notifications after dispose.
    });
  });

  test('an opponent who has gone hands you the win, ending the match there', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final c = make(async, repo, VanishingOpponent());
      for (var r = 0; r < 3; r++) {
        async.elapse(Duration(milliseconds: roundDurationMs(c.roundNo) + resolveHoldMs + 50));
      }
      expect(c.outcome, DuelOutcome.won);
      final round = c.roundNo;
      async.elapse(const Duration(seconds: 30));
      expect(c.roundNo, round, reason: 'no more rounds after they left');
      c.dispose();
    });
  });

  test('a planned question set is what both players answer (0030)', () {
    fakeAsync((async) {
      final repo = FakeRepo();
      final clock = async.getClock(DateTime(2026));
      final c = DuelController(
        repo: repo,
        opponent: FixedBot(),
        hero: 'knight',
        yourBaselineMs: 4000,
        rand: () => 0.5,
        now: () => clock.now().millisecondsSinceEpoch,
        questions: parseQuestions([
          {
            'term': '猫',
            'reading': 'ねこ',
            'options': ['нохой', 'муур', 'загас', 'шувуу'],
            'answer': 1,
          },
          {
            'term': '犬',
            'reading': 'いぬ',
            'options': ['нохой', 'муур', 'загас', 'шувуу'],
            'answer': 0,
          },
        ]),
        cardForTerm: (term) async => 'mine-$term',
      )..load();
      async.flushMicrotasks();

      expect(c.shared, isTrue);
      expect(c.term, '猫');
      expect(c.quiz!.map((o) => o.answerText), ['нохой', 'муур', 'загас', 'шувуу'], reason: "the server's order");
      expect(c.quiz!.indexWhere((o) => o.correct), 1);
      expect(repo.practiceCalls, 0, reason: 'no own-deck fetch when the words come with the match');

      answerRight(c);
      async.flushMicrotasks();
      // Logged against MY card for that word, as battle — never scheduled.
      expect(repo.logged.single, {'card': 'mine-猫', 'rating': 'good', 'source': 'battle'});

      async.elapse(const Duration(milliseconds: 15000));
      expect(c.roundNo, 2);
      expect(c.term, '犬');
      c.dispose();
    });
  });
}
