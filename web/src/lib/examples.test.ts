import { test } from "node:test";
import assert from "node:assert/strict";
import {
  MAX_SENTENCE_CHARS,
  findExample,
  highlightParts,
  parseFurigana,
  pickExample,
  plainOf,
  rubyUnits,
  usesAsWord,
  wordStem,
} from "./examples.ts";

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

test("find: two callers at once share one request; a failure isn't remembered", async () => {
  let calls = 0;
  const ok = (async () => {
    calls++;
    await new Promise((r) => setTimeout(r, 5));
    return new Response(JSON.stringify({ data: [s("私は羊の群を見た。", [en("I saw a flock of sheep.")])] }));
  }) as unknown as typeof fetch;
  const [a, b] = await Promise.all([findExample("群", ok), findExample("群", ok)]);
  assert.equal(calls, 1);
  assert.deepEqual(a, b);
  assert.equal((await findExample("群", ok))?.en, "I saw a flock of sheep.");
  assert.equal(calls, 1, "remembered");

  let failed = 0;
  const busy = (async () => {
    failed++;
    return new Response("busy", { status: 503 });
  }) as unknown as typeof fetch;
  assert.equal(await findExample("量子論", busy), null);
  assert.equal(await findExample("量子論", busy), null);
  assert.equal(failed, 2);
});

// Readings — the same cases as the furigana tests in
// mobile/test/word_example_test.dart.
test("furigana: one reading per kanji when they split, else over the whole word", () => {
  assert.deepEqual(parseFurigana("[勉強|べん|きょう]は[難|むずか]しい。"), [
    { text: "勉", reading: "べん" },
    { text: "強", reading: "きょう" },
    { text: "は", reading: "" },
    { text: "難", reading: "むずか" },
    { text: "し", reading: "" },
    { text: "い", reading: "" },
    { text: "。", reading: "" },
  ]);
  assert.deepEqual(parseFurigana("[今日|きょう]"), [{ text: "今日", reading: "きょう" }]);
  assert.equal(plainOf("[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。"), "私は羊の群を見た。");
});

test("furigana: malformed markup is no reading at all", () => {
  assert.equal(parseFurigana("[私|わたし"), null);
  assert.equal(parseFurigana("私]は"), null);
  assert.equal(parseFurigana("[私|]は"), null);
  assert.equal(plainOf("[私|わたし"), "");
});

test("furigana: shown only while it describes the sentence — an edited one goes without", () => {
  const f = "[私|わたし]は[見|み]た。";
  assert.equal(rubyUnits("私は見た。", f)[0].reading, "わたし");
  const edited = rubyUnits("私が見た。", f);
  assert.equal(edited.map((u) => u.text).join(""), "私が見た。");
  assert.ok(edited.every((u) => u.reading === ""));
});

test("pick: the sentence's reading comes with it, if it matches the sentence", () => {
  const withReading = (ja: string, reading: string) => ({
    ...s(ja, [en("I saw a flock of sheep.")]),
    transcriptions: [{ script: "Hrkt", text: reading }],
  });
  assert.equal(
    pickExample("群", [withReading("私は羊の群を見た。", "[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。")])?.furigana,
    "[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。"
  );
  assert.equal(pickExample("群", [withReading("私は羊の群を見た。", "[私|わたし]は")])?.furigana, undefined);
});
