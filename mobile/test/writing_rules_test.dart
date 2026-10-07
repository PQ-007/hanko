import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/writing/writing_rules.dart';

void main() {
  test('only words with a kanji are worth writing', () {
    expect(hasKanji('連帯'), isTrue);
    expect(hasKanji('食べる'), isTrue);
    expect(hasKanji('時々'), isTrue);
    expect(hasKanji('ありがとう'), isFalse);
    expect(hasKanji('コーヒー'), isFalse);
  });

  test('any of the guesses being the word counts, not just the top one', () {
    expect(matchingCandidate('連帯', ['連滞', '連帯', '運帯']), '連帯');
    expect(matchingCandidate('連帯', ['連滞', '運帯']), isNull);
  });

  test('stray spaces between strokes groups do not matter', () {
    expect(matchingCandidate('食べる', ['食 べる']), '食 べる');
  });

  test('the whole word has to be there', () {
    expect(matchingCandidate('食べる', ['食べ']), isNull);
    expect(matchingCandidate('連帯', ['連']), isNull);
  });
}
