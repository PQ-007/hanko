import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/battle/question_kinds.dart';
import 'package:mobile/features/battle/rules.dart';

QuizWord w(String id, String term, {String? reading, String? mn}) =>
    QuizWord(id: id, term: term, reading: reading, meaning: null, meaningMn: mn);

/// Every kanji these tests use, as if learned in writing lessons.
const all = {'連', '帯', '国', '際', '合'};

void main() {
  group('eligibleKinds', () {
    test('only kanji learned in a writing lesson are asked to be written', () {
      final word = w('1', '連帯', mn: 'x');
      expect(eligibleKinds(word, canWrite: true, learned: const {}), {QuestionKind.meaning});
      expect(eligibleKinds(word, canWrite: true, learned: const {'連'}), {QuestionKind.meaning}, reason: 'every kanji, not just one');
      expect(eligibleKinds(word, canWrite: true, learned: const {'連', '帯'}), QuestionKind.values.toSet());
    });

    test('a kanji word can be asked by meaning or written', () {
      expect(eligibleKinds(w('1', '連帯', reading: 'れんたい', mn: 'эв нэгдэл'), canWrite: true, learned: all), QuestionKind.values.toSet());
    });

    test('no handwriting recogniser, no writing questions', () {
      expect(eligibleKinds(w('1', '連帯', mn: 'x'), canWrite: false, learned: all), {QuestionKind.meaning});
    });

    test('a kana word has nothing to write', () {
      expect(eligibleKinds(w('1', 'ありがとう', mn: 'баярлалаа'), canWrite: true, learned: all), {QuestionKind.meaning});
    });

    test('a word with too many kanji is asked by meaning', () {
      expect(eligibleKinds(w('1', '国際連合', mn: 'x'), canWrite: true, learned: all), {QuestionKind.meaning});
    });
  });

  group('pickKind', () {
    final kindsAll = QuestionKind.values.toSet();

    test('weights split the range: meaning 3, write 2 (of 5)', () {
      expect(pickKind(kindsAll, () => 0.0), QuestionKind.meaning);
      expect(pickKind(kindsAll, () => 0.59), QuestionKind.meaning);
      expect(pickKind(kindsAll, () => 0.61), QuestionKind.write);
      expect(pickKind(kindsAll, () => 0.99), QuestionKind.write);
    });

    test('only eligible and allowed kinds are picked', () {
      expect(pickKind({QuestionKind.meaning}, () => 0.99), QuestionKind.meaning);
      expect(pickKind(kindsAll, () => 0.99, allowed: {QuestionKind.meaning}), QuestionKind.meaning);
    });
  });

  test('writing time scales with the kanji; speed is judged against it', () {
    expect(timeLimitFor(QuestionKind.write, '連帯'), 24000);
    expect(timeLimitFor(QuestionKind.write, '食べる'), 12000);
    expect(timeLimitFor(QuestionKind.meaning, '連帯'), questionTimeLimitMs);
    expect(speedFor(5000, 24000), 'easy', reason: 'under a third of its time');
    expect(speedFor(12000, 24000), 'good');
    expect(speedFor(20000, 24000), 'hard');
  });
}
