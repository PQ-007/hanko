import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/dictionary.dart';
import 'package:mobile/core/local_db.dart';
import 'package:mobile/features/audio/example_sentences.dart';
import 'package:mobile/features/decks/example_section.dart';
import 'package:mobile/features/review/example_line.dart';
import 'package:mobile/models/library.dart';
import 'package:mobile/models/queue_card.dart';

/// Tatoeba answers [sentences] (ja → en) for every query; Google Translate
/// answers "MN:" + the text, unclipped.
http.Client fakeWeb(Map<String, String> sentences, {List<String>? queries}) => MockClient((req) async {
      if (req.url.host == 'api.tatoeba.org') {
        queries?.add(req.url.queryParameters['q']!);
        final data = [
          for (final e in sentences.entries)
            {
              'text': e.key,
              'is_unapproved': false,
              'translations': [
                {'text': e.value, 'lang': 'eng', 'is_direct': true, 'is_unapproved': false},
              ],
            },
        ];
        return http.Response(jsonEncode({'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      final q = req.url.queryParameters['q']!;
      return http.Response(
        jsonEncode([
          [
            ['MN:$q', q],
          ],
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

ExampleController controllerFor(http.Client web, {WordExample? initial}) {
  final tmp = Directory.systemTemp.createTempSync();
  addTearDown(() => tmp.deleteSync(recursive: true));
  return ExampleController(
    sentences: ExampleSentences(client: web, dir: () async => tmp),
    dictionary: Dictionary(client: web),
    initial: initial,
  );
}

const _eat = {'りんごを食べる。': 'I eat an apple, every morning.'};

void main() {
  group('rows', () {
    test('a row with no sentence has no example; parts come back trimmed', () {
      expect(WordExample.fromRow({}), isNull);
      expect(WordExample.fromRow({'example_ja': '  ', 'example_en': 'x'}), isNull);
      final e = WordExample.fromRow({'example_ja': ' 食べる。 ', 'example_en': 'Eat.'})!;
      expect((e.ja, e.en, e.mn), ('食べる。', 'Eat.', ''));
    });

    test('empty parts are written as null, so clearing really clears', () {
      expect(const WordExample(ja: 'a').toRow(), {'example_ja': 'a', 'example_en': null, 'example_mn': null});
    });

    test('queue rows carry the example, and rows from before 0031 still parse', () {
      final base = {
        'card_id': 'c',
        'word_id': 'w',
        'deck_id': 'd',
        'template': 'recognition',
        'state': 'new',
        'due_at': '2026-10-15T00:00:00Z',
        'term': '食べる',
      };
      expect(QueueCard.fromJson(base).example, isNull);
      final c = QueueCard.fromJson({...base, 'example_ja': 'りんごを食べる。', 'example_mn': 'Алим идэх.'});
      expect(c.example!.mn, 'Алим идэх.');
      expect(c.copyWith(state: 'learning').example!.ja, 'りんごを食べる。');
    });

    test('the offline cache keeps the example', () async {
      final db = LocalDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.cacheQueue([
        CachedCardsCompanion.insert(
          cardId: 'c',
          wordId: 'w',
          deckId: 'd',
          template: 'recognition',
          state: 'new',
          learningStep: 0,
          dueAt: DateTime(2026, 10, 15),
          intervalDays: 0,
          repetitions: 0,
          easeFactor: 2.5,
          term: '食べる',
          position: 0,
          exampleJa: const Value('りんごを食べる。'),
          exampleEn: const Value('I eat an apple.'),
        ),
      ]);
      final row = (await db.cachedQueue()).single;
      expect((row.exampleJa, row.exampleEn, row.exampleMn), ('りんごを食べる。', 'I eat an apple.', null));
    });
  });

  test('a v4 database on the phone upgrades to v5 with its rows intact', () async {
    // Built at v5, then put back into v4's shape: the example columns
    // dropped and the version wound back — what every installed app has.
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/hanko.sqlite');
    var db = LocalDb.forTesting(NativeDatabase(file));
    await db.customStatement(
      "insert into cached_cards (card_id, word_id, deck_id, template, state, learning_step, due_at, interval_days, repetitions, ease_factor, term, position) "
      "values ('c', 'w', 'd', 'recognition', 'new', 0, 0, 0, 0, 2.5, '食べる', 0)",
    );
    for (final t in ['cached_cards', 'offline_deck_cards']) {
      for (final col in ['example_ja', 'example_en', 'example_mn']) {
        await db.customStatement('alter table $t drop column $col');
      }
    }
    await db.customStatement('pragma user_version = 4');
    await db.close();

    db = LocalDb.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final row = (await db.cachedQueue()).single;
    expect((row.term, row.exampleJa), ('食べる', null));
    // Reads alone prove nothing (drift selects *, so a missing column just
    // reads as null): write a sentence into both tables.
    await db.customStatement("update cached_cards set example_ja = '文。'");
    await db.customStatement(
      "insert into offline_deck_cards (card_id, word_id, deck_id, template, state, learning_step, due_at, interval_days, repetitions, ease_factor, term, example_ja, example_en, example_mn) "
      "values ('c', 'w', 'd', 'recognition', 'new', 0, 0, 0, 0, 2.5, '食べる', '文。', 'A.', 'Б.')",
    );
    expect((await db.cachedQueue()).single.exampleJa, '文。');
  });

  group('highlight', () {
    const mark = TextStyle(fontWeight: FontWeight.bold);
    String marked(List<TextSpan> spans) => spans.where((s) => s.style == mark).map((s) => s.text).join();

    test('the word itself, else its stem, else nothing', () {
      expect(marked(highlightSpans('りんごを食べる。', '食べる', mark)), '食べる');
      expect(marked(highlightSpans('りんごを食べた。', '食べる', mark)), '食べ');
      expect(marked(highlightSpans('こんにちは。', '食べる', mark)), '');
      expect(highlightSpans('りんごを食べた。', '食べる', mark).map((s) => s.text).join(), 'りんごを食べた。');
    });
  });

  group('controller', () {
    test('a suggestion fills the sentence and translates it whole', () async {
      final c = controllerFor(fakeWeb(_eat));
      c.suggest('食べる', context: '食べました');
      final e = await c.settle('食べました');
      expect(e.ja, 'りんごを食べる。');
      expect(e.en, 'I eat an apple, every morning.');
      // Not cut at the comma the way a word's gloss is.
      expect(e.mn, 'MN:I eat an apple, every morning.');
    });

    test('nothing on Tatoeba: empty, and says so', () async {
      final c = controllerFor(fakeWeb({}));
      c.suggest('食べる');
      expect((await c.settle('食べる')).isEmpty, isTrue);
      expect(c.none, isTrue);
    });

    test('a suggestion for a term the user has typed past is not saved under the new one', () async {
      final c = controllerFor(fakeWeb(_eat));
      c.suggest('食べる');
      await c.settle('食べる');
      expect((await c.settle('飲む')).isEmpty, isTrue);
    });

    test('what the user typed wins: no later suggestion replaces it', () async {
      final queries = <String>[];
      final c = controllerFor(fakeWeb(_eat, queries: queries));
      c.ja.text = '自分の文。';
      c.edited();
      c.suggest('食べる');
      expect(queries, isEmpty);
      final e = await c.settle('全然違う');
      expect(e.ja, '自分の文。');
    });

    test('a new term replaces an untouched suggestion', () async {
      final c = controllerFor(fakeWeb(_eat));
      c.suggest('食べる');
      await c.settle('食べる');
      c.suggest('');
      expect(c.isEmpty, isTrue);
    });

    test('a saved sentence is kept as the form opens; research replaces it', () async {
      final c = controllerFor(fakeWeb(_eat), initial: const WordExample(ja: '古い文。', en: 'Old.', mn: 'Хуучин.'));
      c.suggest('食べる');
      expect((await c.settle('食べる')).ja, '古い文。');
      c.research('食べる');
      expect((await c.settle('食べる')).ja, 'りんごを食べる。');
    });

    test('English typed by hand gets its Mongolian on save', () async {
      final c = controllerFor(fakeWeb({}));
      c.ja.text = '文。';
      c.en.text = 'A sentence.';
      c.edited();
      expect((await c.settle('x')).mn, 'MN:A sentence.');
    });
  });
}
