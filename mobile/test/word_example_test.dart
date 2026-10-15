import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold, Brightness;
import 'package:mobile/core/dictionary.dart';
import 'package:mobile/core/furigana.dart';
import 'package:mobile/core/theme.dart';
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
      expect(const WordExample(ja: 'a').toRow(), {'example_ja': 'a', 'example_en': null, 'example_mn': null, 'example_furigana': null});
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
      for (final col in ['example_ja', 'example_en', 'example_mn', 'example_furigana']) {
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

  test('a v5 database on the phone upgrades to v6: the reading column is added to both tables', () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/hanko.sqlite');
    var db = LocalDb.forTesting(NativeDatabase(file));
    await db.cachedQueue(); // opens (and creates) it
    for (final t in ['cached_cards', 'offline_deck_cards']) {
      await db.customStatement('alter table $t drop column example_furigana');
    }
    await db.customStatement('pragma user_version = 5');
    await db.close();

    db = LocalDb.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    await db.customStatement(
      "insert into cached_cards (card_id, word_id, deck_id, template, state, learning_step, due_at, interval_days, repetitions, ease_factor, term, position, example_furigana) "
      "values ('c', 'w', 'd', 'recognition', 'new', 0, 0, 0, 0, 2.5, '食べる', 0, '[食|た]べる')",
    );
    await db.customStatement(
      "insert into offline_deck_cards (card_id, word_id, deck_id, template, state, learning_step, due_at, interval_days, repetitions, ease_factor, term, example_furigana) "
      "values ('c', 'w', 'd', 'recognition', 'new', 0, 0, 0, 0, 2.5, '食べる', '[食|た]べる')",
    );
    expect((await db.cachedQueue()).single.exampleFurigana, '[食|た]べる');
  });

  group('furigana', () {
    // The same cases as the furigana tests in web/src/lib/examples.test.ts.
    test('one reading per kanji when they split, else over the whole word', () {
      expect(parseFurigana('[勉強|べん|きょう]は[難|むずか]しい。'), const [
        RubyUnit('勉', 'べん'),
        RubyUnit('強', 'きょう'),
        RubyUnit('は'),
        RubyUnit('難', 'むずか'),
        RubyUnit('し'),
        RubyUnit('い'),
        RubyUnit('。'),
      ]);
      expect(parseFurigana('[今日|きょう]'), const [RubyUnit('今日', 'きょう')]);
      expect(plainOf('[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。'), '私は羊の群を見た。');
    });

    test('malformed markup is no reading at all', () {
      expect(parseFurigana('[私|わたし'), isNull);
      expect(parseFurigana('私]は'), isNull);
      expect(parseFurigana('[私|]は'), isNull);
      expect(plainOf('[私|わたし'), '');
    });

    test('shown only while it describes the sentence — an edited one goes without', () {
      const f = '[私|わたし]は[見|み]た。';
      expect(rubyUnits('私は見た。', f).first.reading, 'わたし');
      final edited = rubyUnits('私が見た。', f);
      expect(edited.map((u) => u.text).join(), '私が見た。');
      expect(edited.every((u) => u.reading.isEmpty), isTrue);
    });

    test("pick: the sentence's reading comes with it, if it matches the sentence", () {
      Map<String, dynamic> withReading(String ja, String reading) => {
            'text': ja,
            'is_unapproved': false,
            'translations': [
              {'text': 'I saw a flock of sheep.', 'lang': 'eng', 'is_direct': true, 'is_unapproved': false},
            ],
            'transcriptions': [
              {'script': 'Hrkt', 'text': reading},
            ],
          };
      expect(pickExample('群', [withReading('私は羊の群を見た。', '[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。')])!.furigana,
          '[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。');
      expect(pickExample('群', [withReading('私は羊の群を見た。', '[私|わたし]は')])!.furigana, isNull);
    });

    test("a suggestion's reading is saved with it, and dropped once the sentence is edited", () async {
      const f = '[私|わたし]は[群|むれ]を[見|み]た。';
      final c = controllerFor(MockClient((req) async {
        if (req.url.host == 'api.tatoeba.org') {
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'data': [
                  {
                    'text': '私は群を見た。',
                    'is_unapproved': false,
                    'translations': [
                      {'text': 'I saw a flock.', 'lang': 'eng', 'is_direct': true, 'is_unapproved': false},
                    ],
                    'transcriptions': [
                      {'script': 'Hrkt', 'text': f},
                    ],
                  },
                ],
              })),
              200);
        }
        return http.Response.bytes(utf8.encode(jsonEncode([
          [
            ['MN', 'x'],
          ],
        ])), 200);
      }));
      c.suggest('群');
      while (c.looking || c.translating) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.take('群').now.furigana, f);
      expect(c.value.toRow()['example_furigana'], f);
      c.ja.text = '私が群を見た。';
      c.edited();
      expect(c.value.furigana, isNull);
      expect(c.value.toRow()['example_furigana'], isNull);
      expect(WordExample.fromRow({'example_ja': '私が群を見た。', 'example_furigana': f})!.furigana, isNull);
    });

    testWidgets('the review line draws the reading over its kanji, and the word still marked', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildHankoTheme(Brightness.light),
        home: const Scaffold(
          body: ExampleLine(
            term: '群',
            example: WordExample(ja: '私は羊の群を見た。', en: 'I saw a flock.', mn: 'Би сүрэг харсан.', furigana: '[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。'),
          ),
        ),
      ));
      expect(find.text('わたし'), findsOneWidget);
      expect(find.text('むれ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
    /// What a save of [term] ends up writing: what goes in now, or what
    /// lands afterwards.
    Future<WordExample> saved(ExampleController c, String term) async {
      final r = c.take(term);
      return r.later == null ? r.now : (await r.later) ?? r.now;
    }

    /// Lets the controller finish what it is fetching.
    Future<void> idle(ExampleController c) async {
      while (c.looking || c.translating) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a ready suggestion goes in with the word, translated whole', () async {
      final c = controllerFor(fakeWeb(_eat));
      c.suggest('食べる', context: '食べました');
      await idle(c);
      final r = c.take('食べました');
      expect(r.later, isNull);
      expect(r.now.ja, 'りんごを食べる。');
      expect(r.now.en, 'I eat an apple, every morning.');
      // Not cut at the comma the way a word's gloss is.
      expect(r.now.mn, 'MN:I eat an apple, every morning.');
    });

    test('a save never waits: a sentence still on its way lands afterwards, even once the form is cleared', () async {
      final c = controllerFor(fakeWeb(_eat));
      c.suggest('食べる');
      final r = c.take('食べる');
      expect(r.now.isEmpty, isTrue);
      expect(r.later, isNotNull);
      c.clear(); // the add sheet resets right after saving
      final e = (await r.later)!;
      expect((e.ja, e.mn), ('りんごを食べる。', 'MN:I eat an apple, every morning.'));
    });

    test('nothing on Tatoeba: nothing saved, now or later, and it says so', () async {
      final c = controllerFor(fakeWeb({}));
      c.suggest('食べる');
      expect(await c.take('食べる').later, isNull);
      await idle(c);
      expect(c.none, isTrue);
      expect(c.take('食べる').now.isEmpty, isTrue);
    });

    test('a suggestion for a term the user has typed past is not saved under the new one', () async {
      final c = controllerFor(fakeWeb(_eat));
      c.suggest('食べる');
      expect(c.take('飲む').later, isNull, reason: 'still searching');
      await idle(c);
      expect((await saved(c, '飲む')).isEmpty, isTrue, reason: 'found');
    });

    test('what the user typed wins: no later suggestion replaces it', () async {
      final queries = <String>[];
      final c = controllerFor(fakeWeb(_eat, queries: queries));
      c.ja.text = '自分の文。';
      c.edited();
      c.suggest('食べる');
      expect(queries, isEmpty);
      expect((await saved(c, '全然違う')).ja, '自分の文。');
    });

    test('a new term replaces an untouched suggestion', () async {
      final c = controllerFor(fakeWeb(_eat));
      c.suggest('食べる');
      await idle(c);
      c.suggest('');
      expect(c.isEmpty, isTrue);
    });

    test('a saved sentence is kept as the form opens; research replaces it', () async {
      final c = controllerFor(fakeWeb(_eat), initial: const WordExample(ja: '古い文。', en: 'Old.', mn: 'Хуучин.'));
      c.suggest('食べる');
      expect((await saved(c, '食べる')).ja, '古い文。');
      c.research('食べる');
      expect((await saved(c, '食べる')).ja, 'りんごを食べる。');
    });

    test('English typed by hand: the sentence goes in whole, once its Mongolian is back', () async {
      final c = controllerFor(fakeWeb({}));
      c.ja.text = '文。';
      c.en.text = 'A sentence.';
      c.edited();
      final r = c.take('x');
      expect(r.now.isEmpty, isTrue);
      expect((await r.later)!.mn, 'MN:A sentence.');
    });
  });
}
