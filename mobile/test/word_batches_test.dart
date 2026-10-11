import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/word_batches.dart';
import 'package:mobile/models/library.dart';

Word w(String term, DateTime added, {String? reading}) =>
    Word(id: term, deckId: 'd', term: term, reading: reading, dateAdded: added);

void main() {
  final now = DateTime(2026, 10, 11, 15, 0);
  // A camera capture: one insert, one timestamp to the microsecond.
  final capture = DateTime(2026, 10, 11, 14, 30, 5, 123, 456);
  final words = [
    w('猫', DateTime(2026, 10, 1, 9), reading: 'ねこ'),
    w('犬', DateTime(2026, 10, 11, 8), reading: 'いぬ'),
    w('軌道', capture, reading: 'きどう'),
    w('群', capture, reading: 'むれ'),
    w('原子核', capture, reading: 'げんしかく'),
    w('ありがとう', DateTime(2026, 10, 9, 20)),
  ];

  test('the latest batch is the words sharing the newest timestamp', () {
    final b = latestBatch(words, now)!;
    expect(b.at, capture);
    expect(b.words.map((x) => x.term), ['軌道', '群', '原子核']);
  });

  test('one microsecond apart is not the same batch', () {
    final apart = [
      w('a', capture),
      w('b', capture.add(const Duration(microseconds: 1))),
    ];
    expect(latestBatch(apart, now), isNull);
    expect(wordBatches(apart), isEmpty);
  });

  test('no batch to offer when the newest addition is a single word, or old', () {
    expect(latestBatch([...words, w('新', DateTime(2026, 10, 11, 14, 59))], now), isNull,
        reason: 'the newest addition was one word, added by hand');
    expect(latestBatch(words, now.add(const Duration(days: 2))), isNull);
    expect(latestBatch(const [], now), isNull);
  });

  test('all batches, newest first, singles left out', () {
    final older = DateTime(2026, 10, 2, 10);
    final bs = wordBatches([...words, w('x', older), w('y', older)]);
    expect(bs.map((b) => b.at), [capture, older]);
    expect(bs.last.words.map((x) => x.term), ['x', 'y']);
  });

  test('sorts: newest, oldest, and by reading', () {
    expect(sortWords(words, WordSort.newest).first.term, '軌道');
    expect(sortWords(words, WordSort.oldest).first.term, '猫');
    expect(
      sortWords(words, WordSort.alphabetical).map((x) => x.term),
      ['ありがとう', '犬', '軌道', '原子核', '猫', '群'],
    );
  });

  test('added today / this week', () {
    expect(addedWithin(words, AddedWithin.today, now).map((x) => x.term), ['犬', '軌道', '群', '原子核']);
    expect(addedWithin(words, AddedWithin.week, now).map((x) => x.term),
        ['犬', '軌道', '群', '原子核', 'ありがとう']);
    expect(addedWithin(words, AddedWithin.any, now).length, words.length);
  });
}
