import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/dictionary.dart';
import 'package:mobile/features/capture/capture_lookup.dart';

/// A tiny Jisho: surface form → (dictionary form, reading, meaning).
const _jisho = {
  '食べました': ('食べる', 'たべる', 'to eat'),
  '食べた': ('食べる', 'たべる', 'to eat'),
  '猫と': ('猫', 'ねこ', 'cat'),
  'コーヒー': ('コーヒー', null, 'coffee'),
  '昨日寿司': ('昨日', 'きのう', 'yesterday'), // fuzzy, but same first kanji
  '寿司屋': ('ラーメン', null, 'ramen'), // Jisho guessing something else
};

Dictionary fakeDictionary({bool offline = false}) {
  return Dictionary(
    client: MockClient((req) async {
      if (offline) throw http.ClientException('offline');
      if (req.url.host == 'jisho.org') {
        final hit = _jisho[req.url.queryParameters['keyword']];
        if (hit == null) return http.Response(jsonEncode({'data': []}), 200);
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'data': [
              {
                'slug': hit.$1,
                'japanese': [
                  {'word': hit.$1, 'reading': hit.$2 ?? hit.$1},
                ],
                'senses': [
                  {'english_definitions': [hit.$3]},
                ],
              },
            ],
          })),
          200,
        );
      }
      final q = req.url.queryParameters['q'];
      return http.Response.bytes(
        utf8.encode(jsonEncode([
          [
            ['mn:$q', q],
          ],
        ])),
        200,
      );
    }),
  );
}

void main() {
  test('found words come back in dictionary form, translated', () async {
    final items = await resolveCapture(['食べました', 'コーヒー'], fakeDictionary());
    expect(items.map((i) => i.draft.term), ['食べる', 'コーヒー']);
    final eat = items.first;
    expect(eat.found, isTrue);
    expect(eat.draft.reading, 'たべる');
    expect(eat.draft.meaning, 'to eat');
    expect(eat.draft.meaningMn, 'mn:to eat');
    expect(items[1].draft.reading, isNull, reason: 'a kana word has no separate reading');
  });

  test('two forms of one word become one item', () async {
    final items = await resolveCapture(['食べました', '猫と', '食べた'], fakeDictionary());
    expect(items.map((i) => i.draft.term), ['食べる', '猫']);
  });

  test("a lookup that isn't the same word keeps the photographed term, blank", () async {
    final items = await resolveCapture(['寿司屋', 'ゴミ'], fakeDictionary());
    expect(items.map((i) => (i.draft.term, i.found)), [('寿司屋', false), ('ゴミ', false)]);
    expect(items.first.draft.meaning, isNull);
  });

  test('offline, every word is kept as photographed', () async {
    var progress = 0;
    final items = await resolveCapture(
      ['食べました', 'コーヒー'],
      fakeDictionary(offline: true),
      onProgress: (d, _) => progress = d,
    );
    expect(items.map((i) => i.draft.term), ['食べました', 'コーヒー']);
    expect(items.every((i) => !i.found && i.selected), isTrue);
    expect(progress, 2);
  });

  test('many words keep their order through the parallel lookups', () async {
    final terms = [for (var i = 0; i < 20; i++) '語$i'];
    final items = await resolveCapture(terms, fakeDictionary());
    expect(items.map((i) => i.draft.term), terms);
  });
}
