import { test } from "node:test";
import assert from "node:assert/strict";
import { MAX_SENTENCE_CHARS, highlightParts, pickExample, usesAsWord, wordStem } from "./examples.ts";

// The same cases as mobile/test/example_sentences_test.dart: change one side,
// change both.

const s = (ja: string, tr: object[], unapproved = false) => ({ text: ja, is_unapproved: unapproved, translations: tr });
const en = (text: string, { direct = true, lang = "eng" } = {}) => ({
  text,
  lang,
  is_direct: direct,
  is_unapproved: false,
});

test("stems: trailing kana and する come off, kana-only words stay whole", () => {
  assert.equal(wordStem("食べる"), "食べ");
  assert.equal(wordStem("担う"), "担");
  assert.equal(wordStem("勉強する"), "勉強");
  assert.equal(wordStem("軌道"), "軌道");
  assert.equal(wordStem("ありがとう"), "ありがとう");
});

test("a word inside a longer kanji compound is not the word", () => {
  assert.equal(usesAsWord("私は羊の群を見た。", "群"), true);
  assert.equal(usesAsWord("彼女抜群ですよ。", "群"), false);
  assert.equal(usesAsWord("担当は私です。", "担"), false);
  assert.equal(usesAsWord("彼が責任を担った。", "担"), true);
  assert.equal(usesAsWord("抜群の群だ。", "群"), true);
});

test("a kanji neighbour rules a sentence out, even when it is a separate word", () => {
  assert.equal(usesAsWord("彼は若い頃は実に無軌道だった。", "軌道"), false);
  assert.equal(usesAsWord("衛星は今軌道に乗っている。", "軌道"), false);
});

test("picks a sentence that uses the word, not one that merely contains it", () => {
  const data = [
    s("彼女抜群ですよ。", [en("She stands out from the rest.")]),
    s("３０００人を超える群集。", [en("A crowd of more than three thousand.")]),
    s("私は羊の群を見た。", [en("I saw a flock of sheep.")]),
  ];
  assert.deepEqual(pickExample("群", data), { ja: "私は羊の群を見た。", en: "I saw a flock of sheep." });
  assert.equal(pickExample("担う", [s("担当は私です。", [en("I'm in charge.")])]), null);
  assert.equal(pickExample("担う", [s("彼が責任を担った。", [en("He took responsibility.")])])?.ja, "彼が責任を担った。");
});

test("prefers the exact form, then a mid-length sentence over a bare one", () => {
  const data = [
    s("食べる。", [en("Eat.")]),
    s("昨日寿司を食べた。", [en("I ate sushi yesterday.")]),
    s("朝ごはんを食べるのが好きです。", [en("I like eating breakfast.")]),
  ];
  assert.equal(pickExample("食べる", data)?.ja, "朝ごはんを食べるのが好きです。");
});

test("skips unapproved, untranslated, too long; takes a direct translation first", () => {
  const long = `${"とても".repeat(12)}軌道。`;
  assert.ok(long.length > MAX_SENTENCE_CHARS);
  const data = [
    s("衛星が軌道に乗った。", [en("The satellite reached orbit.")], true),
    s("軌道を外れた衛星。", [en("Un satellite.", { lang: "fra" })]),
    s(long, [en("Very long.")]),
    s("衛星は軌道に乗っている。", [en("Indirect.", { direct: false }), en("The satellite is in orbit.")]),
  ];
  assert.equal(pickExample("軌道", data)?.en, "The satellite is in orbit.");
  assert.equal(pickExample("軌道", null), null);
  assert.equal(pickExample("量子論", []), null);
});

// Same cases as the highlight test in mobile/test/word_example_test.dart.
test("highlight: the word itself, else its stem, else nothing", () => {
  assert.equal(highlightParts("りんごを食べる。", "食べる").mark, "食べる");
  assert.equal(highlightParts("りんごを食べた。", "食べる").mark, "食べ");
  assert.equal(highlightParts("こんにちは。", "食べる").mark, "");
  const p = highlightParts("りんごを食べた。", "食べる");
  assert.equal(p.before + p.mark + p.after, "りんごを食べた。");
});
