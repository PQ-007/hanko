import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/dictionary.dart';
import 'package:mobile/features/library/export_text.dart';
import 'package:mobile/models/library.dart';

// Parsing ports of web/src/lib/jisho.ts, translate.ts and wordText.ts. The
// phone now calls Jisho and Google directly, so these must read the same
// responses the same way the web server does.

Word w({required String term, String? reading, String? meaning, String? mn, DateTime? added}) =>
    Word(
      id: term,
      deckId: 'd',
      term: term,
      reading: reading,
      meaning: meaning,
      meaningMn: mn,
      dateAdded: added ?? DateTime(2026),
    );

void main() {
  group('parseJisho', () {
    test('takes the dictionary form, reading and first three senses', () {
      final r = parseJisho({
        'data': [
          {
            'slug': '担う',
            'japanese': [
              {'word': '担う', 'reading': 'になう'},
            ],
            'senses': [
              {'english_definitions': ['to carry on one\'s shoulder']},
              {'english_definitions': ['to bear', 'to shoulder']},
              {'english_definitions': ['to take responsibility']},
              {'english_definitions': ['ignored fourth sense']},
            ],
          },
        ],
      });
      expect(r.word, '担う');
      expect(r.reading, 'になう');
      expect(r.meaning, "to carry on one's shoulder; to bear, to shoulder; to take responsibility");
    });

    test('a kana-only word falls back to the slug, then the reading', () {
      expect(
        parseJisho({
          'data': [
            {
              'slug': 'ありがとう',
              'japanese': [
                {'reading': 'ありがとう'},
              ],
              'senses': [],
            },
          ],
        }).word,
        'ありがとう',
      );
      expect(
        parseJisho({
          'data': [
            {
              'japanese': [
                {'reading': 'すごい'},
              ],
            },
          ],
        }).word,
        'すごい',
      );
    });

    // Jisho lists an entry under its common spelling: searching 附属 returns
    // the 付属 entry, with 附属 as an alternative writing.
    final variant = {
      'data': [
        {
          'slug': '付属',
          'japanese': [
            {'word': '付属', 'reading': 'ふぞく'},
            {'word': '附属', 'reading': 'ふぞく'},
          ],
          'senses': [
            {'english_definitions': ['attached']},
          ],
        },
        {
          'slug': '籠る',
          'japanese': [
            {'word': '篭る', 'reading': 'こもる'},
            {'word': '籠る', 'reading': 'こもる'},
          ],
          'senses': [
            {'english_definitions': ['to shut oneself in']},
          ],
        },
      ],
    };

    test("the kanji as typed is kept when it's one of the entry's writings", () {
      final r = parseJisho(variant, term: '附属');
      expect(r.word, '附属', reason: 'not swapped for the common 付属');
      expect(r.reading, 'ふぞく');
      expect(r.meaning, 'attached');
    });

    test('a later entry that has the typed writing wins over the first', () {
      final r = parseJisho(variant, term: '籠る');
      expect(r.word, '籠る');
      expect(r.meaning, 'to shut oneself in', reason: 'meaning comes from the matching entry');
    });

    test('a form no entry lists (conjugated) still gets the dictionary form', () {
      expect(parseJisho(variant, term: '付属します').word, '付属');
      expect(parseJisho(variant).word, '付属', reason: 'no term: first entry, as before');
    });

    test('no results or a malformed body is empty, never a throw', () {
      expect(parseJisho({'data': []}).isEmpty, isTrue);
      expect(parseJisho(null).isEmpty, isTrue);
      expect(parseJisho('nonsense').isEmpty, isTrue);
    });
  });

  group('parseTranslation', () {
    test('joins segments', () {
      expect(
        parseTranslation([
          [
            ['муур', 'cat'],
            [' ба нохой', ' and dog'],
          ],
        ], source: 'cat and dog'),
        'муур ба нохой',
      );
    });

    test('dedupes synonym lists Google collapsed to the same word', () {
      expect(
        parseTranslation([
          [
            ['болгоомжтой, Болгоомжтой, ухаалаг', 'careful, cautious, prudent'],
          ],
        ], source: 'careful, cautious, prudent'),
        'болгоомжтой, ухаалаг',
      );
    });

    test('malformed body is empty', () {
      expect(parseTranslation(null, source: 'x'), '');
      expect(parseTranslation([], source: 'x'), '');
    });
  });

  group('deck .txt export matches the web route', () {
    test('front adds the reading only when it differs from the term', () {
      expect(frontText(w(term: '猫', reading: 'ねこ')), '猫 (ねこ)');
      expect(frontText(w(term: 'すし', reading: 'すし')), 'すし');
      expect(frontText(w(term: '猫')), '猫');
    });

    test('back is English then Mongolian; tabs and newlines are escaped', () {
      final txt = buildDeckTxt('My Deck', [
        w(term: '犬', meaning: 'dog\tanimal', mn: 'нохой', added: DateTime(2026, 2)),
        w(term: '猫', reading: 'ねこ', meaning: 'cat', added: DateTime(2026, 1)),
      ]);
      // Oldest first, like the web route's ascending date_added order.
      expect(txt, '猫 (ねこ)\tcat\tMy_Deck\n犬\tdog animal<br>нохой\tMy_Deck');
    });

    test('tags and filenames are ASCII-sanitised like the web', () {
      expect(sanitizeTag('JLPT N3 vocab!'), 'JLPT_N3_vocab');
      expect(sanitizeTag('Монгол'), '');
      expect(sanitizeFilename('Монгол багц'), '_');
      expect(sanitizeFilename(''), 'deck');
    });
  });
}
