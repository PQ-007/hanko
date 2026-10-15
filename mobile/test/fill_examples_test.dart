import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/audio/example_sentences.dart';
import 'package:mobile/features/decks/fill_examples.dart';
import 'package:mobile/models/library.dart';

// The same cases as web/src/app/decks/_lib/fillExamples.test.ts.

const words = [
  (id: '1', term: '食べる'),
  (id: '2', term: '量子論'),
  (id: '3', term: '飲む'),
  (id: '4', term: '見る'),
];

Future<Example?> find(String t) async => t == '量子論' ? null : Example('$t文。', '$t, sentence');
Future<String> translate(String t) async => 'MN:$t';

void main() {
  test('every word gets its own sentence, translated whole; misses are counted', () async {
    final saved = <String, WordExample>{};
    final r = await fillExamples(words, find: find, translate: translate, save: (id, e) async {
      saved[id] = e;
      return true;
    });
    expect(r, (added: 3, missing: 1, skipped: 0));
    expect((saved['1']!.ja, saved['1']!.en, saved['1']!.mn), ('食べる文。', '食べる, sentence', 'MN:食べる, sentence'));
    expect(saved.containsKey('2'), isFalse);
  });

  test('a word that got a sentence meanwhile, or a failed save, is skipped — the rest carry on', () async {
    final r = await fillExamples(words, find: find, translate: translate, save: (id, _) async {
      if (id == '3') throw Exception('offline');
      return id != '4';
    });
    expect(r, (added: 1, missing: 1, skipped: 2));
  });

  test('progress reaches the total, one step per word', () async {
    final seen = <int>[];
    await fillExamples(words,
        find: find, translate: translate, save: (_, _) async => true, onProgress: (n, total) => seen.add(n * 10 + total));
    expect(seen, [14, 24, 34, 44]);
  });

  test('cancelling stops before the next word', () async {
    var asked = 0;
    final r = await fillExamples(
      words,
      find: (t) async {
        asked++;
        return Example('$t。', 'x');
      },
      translate: translate,
      save: (_, _) async => true,
      cancelled: () => asked >= 2,
      concurrency: 1,
    );
    expect(asked, 2);
    expect(r.added, 2);
  });

  test('never more than the limit in flight', () async {
    var live = 0, peak = 0;
    await fillExamples(
      [...words, ...words, ...words],
      find: (t) async {
        live++;
        if (live > peak) peak = live;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        live--;
        return Example('$t。', 'x');
      },
      translate: translate,
      save: (_, _) async => true,
      concurrency: 3,
    );
    expect(peak, 3);
  });
}
