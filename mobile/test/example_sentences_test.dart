import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/audio/example_sentences.dart';

Map<String, dynamic> s(String ja, List<Map<String, dynamic>> tr, {bool unapproved = false}) =>
    {'text': ja, 'is_unapproved': unapproved, 'translations': tr};
Map<String, dynamic> en(String text, {bool direct = true, String lang = 'eng'}) =>
    {'text': text, 'lang': lang, 'is_direct': direct, 'is_unapproved': false};

void main() {
  test('stems: trailing kana and する come off, kana-only words stay whole', () {
    expect(wordStem('食べる'), '食べ');
    expect(wordStem('担う'), '担');
    expect(wordStem('勉強する'), '勉強');
    expect(wordStem('軌道'), '軌道');
    expect(wordStem('ありがとう'), 'ありがとう');
  });

  test('a word inside a longer kanji compound is not the word', () {
    expect(usesAsWord('私は羊の群を見た。', '群'), isTrue);
    expect(usesAsWord('彼女抜群ですよ。', '群'), isFalse);
    expect(usesAsWord('担当は私です。', '担'), isFalse);
    expect(usesAsWord('彼が責任を担った。', '担'), isTrue);
    // One compound use doesn't hide a real use later in the sentence.
    expect(usesAsWord('抜群の群だ。', '群'), isTrue);
  });

  // The price of having no tokenizer, paid on purpose: with no spaces in
  // Japanese, a kanji neighbour can be another word (今 + 軌道) or the same
  // compound (無軌道, "reckless" — a real top hit for 軌道). Losing one good
  // sentence costs nothing when there are fifty to choose from; speaking the
  // wrong word does.
  test('a kanji neighbour rules a sentence out, even when it is a separate word', () {
    expect(usesAsWord('彼は若い頃は実に無軌道だった。', '軌道'), isFalse);
    expect(usesAsWord('衛星は今軌道に乗っている。', '軌道'), isFalse);
  });

  // Real Tatoeba results for 群 and 担う (search matches substrings).
  test('picks a sentence that uses the word, not one that merely contains it', () {
    final data = [
      s('彼女抜群ですよ。', [en('She stands out from the rest.')]),
      s('３０００人を超える群集。', [en('A crowd of more than three thousand.')]),
      s('私は羊の群を見た。', [en('I saw a flock of sheep.')]),
    ];
    final e = pickExample('群', data)!;
    expect(e.ja, '私は羊の群を見た。');
    expect(e.en, 'I saw a flock of sheep.');

    expect(pickExample('担う', [s('担当は私です。', [en("I'm in charge.")])]), isNull);
    expect(pickExample('担う', [s('彼が責任を担った。', [en('He took responsibility.')])])!.ja, '彼が責任を担った。',
        reason: 'a conjugated form counts');
  });

  test('prefers the exact form, then a mid-length sentence over a bare one', () {
    final data = [
      s('食べる。', [en('Eat.')]),
      s('昨日寿司を食べた。', [en('I ate sushi yesterday.')]),
      s('朝ごはんを食べるのが好きです。', [en('I like eating breakfast.')]),
    ];
    expect(pickExample('食べる', data)!.ja, '朝ごはんを食べるのが好きです。');
  });

  test('skips unapproved, untranslated, too long; takes a direct translation first', () {
    final long = '${'とても' * 12}軌道。';
    expect(long.length, greaterThan(maxSentenceChars));
    final data = [
      s('衛星が軌道に乗った。', [en('The satellite reached orbit.')], unapproved: true),
      s('軌道を外れた衛星。', [en('Un satellite.', lang: 'fra')]),
      s(long, [en('Very long.')]),
      s('衛星は軌道に乗っている。', [en('Indirect.', direct: false), en('The satellite is in orbit.')]),
    ];
    expect(pickExample('軌道', data)!.en, 'The satellite is in orbit.');
    expect(pickExample('軌道', null), isNull);
    expect(pickExample('量子論', []), isNull);
  });

  test('find: asks once, then answers from disk — "nothing" included', () async {
    final tmp = Directory.systemTemp.createTempSync();
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      expect(req.url.host, 'api.tatoeba.org');
      final q = req.url.queryParameters['q'];
      final data = q == '群' ? [s('私は羊の群を見た。', [en('I saw a flock of sheep.')])] : [];
      return http.Response.bytes(utf8.encode(jsonEncode({'data': data})), 200);
    });
    final ex = ExampleSentences(client: client, dir: () async => tmp);
    expect((await ex.find('群'))!.en, 'I saw a flock of sheep.');
    expect(await ex.find('量子論'), isNull);
    expect(requests, 2);
    expect((await ex.find('群'))!.ja, '私は羊の群を見た。');
    expect(await ex.find('量子論'), isNull);
    expect(requests, 2, reason: 'both cached');
  });

  test("find: a failed request isn't cached", () async {
    final tmp = Directory.systemTemp.createTempSync();
    var requests = 0;
    final ex = ExampleSentences(
      client: MockClient((_) async {
        requests++;
        return http.Response('busy', 503);
      }),
      dir: () async => tmp,
    );
    expect(await ex.find('群'), isNull);
    expect(await ex.find('群'), isNull);
    expect(requests, 2);
  });
}
