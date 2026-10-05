import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/capture/segment.dart';

void main() {
  test('a noun followed by a particle is suggested alone', () {
    expect(suggestWords(['日本語を勉強します']), ['日本語', '勉強します']);
  });

  test('a verb keeps its ending for the lookup to resolve', () {
    expect(suggestWords(['昨日寿司を食べました。']), ['昨日寿司', '食べました']);
  });

  test('the ending stops at the next particle', () {
    expect(suggestWords(['高くても買う']), ['高くて', '買う']);
  });

  test('katakana words of two or more characters, long marks included', () {
    expect(suggestWords(['コーヒーとケーキ、ア']), ['コーヒー', 'ケーキ']);
  });

  test('hiragana-only text and Latin give nothing', () {
    expect(suggestWords(['とてもおいしい', 'Hello 123']), isEmpty);
  });

  test('と is not taken for a particle, so the lookup has to resolve it', () {
    // 落とす beats "noun + と" often enough to keep と out of the particle
    // set; the dictionary-form dedupe after lookup folds 猫と back into 猫.
    expect(suggestWords(['猫と犬']), ['猫と', '犬']);
  });

  test('each word once, across lines, in reading order', () {
    expect(suggestWords(['猫が好き', '猫も犬']), ['猫', '好き', '犬']);
  });

  test('々 stays inside its word', () {
    expect(suggestWords(['時々行く']), ['時々行く']);
  });

  test('the ending is capped so a clause is not swallowed', () {
    expect(suggestWords(['見させられましたよ']), ['見させられまし']);
  });

  test('a lookup counts only if it is the same word', () {
    expect(lookupMatches('食べました', '食べる'), isTrue);
    expect(lookupMatches('食べました', '飲む'), isFalse);
    expect(lookupMatches('コーヒー', 'コーヒー'), isTrue);
    expect(lookupMatches('コーヒー', 'コーヒー豆'), isFalse);
    expect(lookupMatches('猫', ''), isFalse);
  });
}
