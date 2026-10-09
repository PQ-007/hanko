import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/duel/duel_shared.dart';

// The same cases as the web's sharedQuestions.test.ts and the headToHead test
// in social.test.ts, so the two clients agree on the question set and the
// face-to-face record.
void main() {
  const good = {
    'term': '猫',
    'reading': 'ねこ',
    'options': ['a', 'b', 'c', 'd'],
    'answer': 2,
  };

  group('shared questions', () {
    test('parses a planned question set', () {
      final qs = parseQuestions([good])!;
      expect(qs.single.term, '猫');
      expect(qs.single.reading, 'ねこ');
      expect(qs.single.options, ['a', 'b', 'c', 'd']);
      expect(qs.single.answer, 2);
    });

    test('a missing or malformed set is null, so the duel falls back to its own deck', () {
      expect(parseQuestions(null), isNull);
      expect(parseQuestions([]), isNull);
      expect(parseQuestions('x'), isNull);
      expect(parseQuestions([{...good, 'options': ['a', 'b', 'c']}]), isNull);
      expect(parseQuestions([{...good, 'answer': 4}]), isNull);
      expect(parseQuestions([{...good, 'answer': 1.5}]), isNull);
      expect(parseQuestions([{...good, 'options': ['a', 'b', 'c', 4]}]), isNull);
    });

    test('a bad question is skipped, the good ones kept', () {
      expect(parseQuestions([{'term': 1}, good, null])!.length, 1);
    });

    test('a missing reading is null', () {
      expect(parseQuestions([{...good}..remove('reading')])!.single.reading, isNull);
    });

    test('rounds are 1-based and wrap', () {
      final qs = parseQuestions([good, {...good, 'term': '犬'}])!;
      expect(questionFor(qs, 1).term, '猫');
      expect(questionFor(qs, 2).term, '犬');
      expect(questionFor(qs, 3).term, '猫');
      expect(questionFor(qs, 0).term, '猫');
    });

    test("quiz options keep the server's order and mark only the answer", () {
      final quiz = quizFor(parseQuestions([good])!.single);
      expect(quiz.map((o) => o.answerText), ['a', 'b', 'c', 'd']);
      expect(quiz.map((o) => o.correct), [false, false, true, false]);
      expect(quiz.map((o) => o.term).toSet().length, 4);
    });
  });

  test('headToHead tallies my finished matches per opponent', () {
    const me = 'me', a = 'a', b = 'b';
    Map<String, dynamic> m(String id, String host, String? guest, String? winner, String status, String at,
            [int hostHp = 50, int guestHp = 0]) =>
        {
          'id': id, 'host_id': host, 'guest_id': guest, 'host_hp': hostHp, 'guest_hp': guestHp,
          'winner_id': winner, 'status': status, 'finished_at': at, 'created_at': at,
        };
    final h = headToHead([
      m('1', me, a, me, 'finished', '2026-10-01T10:00:00Z', 64, 0),
      m('2', a, me, a, 'finished', '2026-10-03T10:00:00Z', 30, 0), // I was the guest and lost
      m('3', me, a, null, 'finished', '2026-10-02T10:00:00Z', 0, 0), // draw
      m('4', b, me, me, 'abandoned', '2026-10-04T10:00:00Z', 100, 80), // b left; I won
      m('5', me, a, null, 'active', '2026-10-05T10:00:00Z'), // live — ignored
      m('6', me, null, null, 'lobby', '2026-10-05T10:00:00Z'), // nobody joined — ignored
    ], me);
    final ra = h[a]!;
    expect([ra.wins, ra.losses, ra.draws], [1, 1, 1]);
    expect(ra.matches.map((x) => x.id), ['2', '3', '1'], reason: 'newest first');
    expect([ra.matches[0].myHp, ra.matches[0].theirHp], [0, 30], reason: 'HP from my side as guest');
    expect(ra.total, 3);
    expect(ra.last(5).map((x) => x.id), ['1', '3', '2'], reason: 'the chip strip runs oldest → newest');
    final rb = h[b]!;
    expect([rb.wins, rb.matches[0].abandoned], [1, true]);
  });
}
