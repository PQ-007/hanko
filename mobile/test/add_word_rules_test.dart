import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/dictionary.dart';
import 'package:mobile/features/decks/add_word_rules.dart';

// Same cases as web/src/app/decks/_lib/addWord.test.ts.
void main() {
  const empty = WordFields(term: '生');
  const sei = LookupResult(word: '生', reading: 'せい', meaning: 'life');
  const seikatsu = LookupResult(word: '生活', reading: 'せいかつ', meaning: 'living');

  test('empty fields are filled and remembered as machine-filled', () {
    final r = autofill(empty, {}, sei);
    expect(r.fields, const WordFields(term: '生', reading: 'せい', meaning: 'life'));
    expect(r.auto, {AutoKey.reading, AutoKey.meaning, AutoKey.meaningMn});
    expect(r.meaningChanged, isTrue);
  });

  test('a later match replaces what the machine filled — 生 then 活', () {
    final first = autofill(empty, {}, sei);
    final withMn = first.fields.copyWith(term: '生活', meaningMn: 'амьдрал');
    final r = autofill(withMn, first.auto, seikatsu);
    expect(r.fields.reading, 'せいかつ');
    expect(r.fields.meaning, 'living');
    expect(r.fields.meaningMn, '', reason: 'the old Mongolian described the old word');
    expect(r.fields.term, '生活', reason: 'the term is never rewritten');
  });

  test('what the user typed is theirs', () {
    const typed = WordFields(term: '生', reading: 'なま', meaningMn: 'түүхий');
    final r = autofill(typed, {}, sei);
    expect(r.fields.reading, 'なま');
    expect(r.fields.meaning, 'life');
    expect(r.fields.meaningMn, 'түүхий', reason: 'a hand-typed Mongolian meaning survives a new English one');
    expect(r.auto, {AutoKey.meaning});
  });

  test('the same match again changes nothing and asks for no translation', () {
    final once = autofill(empty, {}, sei);
    final filled = once.fields.copyWith(meaningMn: 'амьдрал');
    final again = autofill(filled, once.auto, sei);
    expect(again.fields, filled);
    expect(again.meaningChanged, isFalse);
  });

  test('the picked match is the one whose word and reading the fields hold', () {
    const nama = LookupResult(word: '生', reading: 'なま', meaning: 'raw');
    final ms = [sei, nama];
    expect(pickedMatch(empty.copyWith(reading: 'なま'), ms), nama);
    expect(pickedMatch(const WordFields(term: ' 生 ', reading: 'せい'), ms), sei);
    expect(pickedMatch(empty.copyWith(reading: 'いき'), ms), isNull);
  });
}
