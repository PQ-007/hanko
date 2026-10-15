import { test } from "node:test";
import assert from "node:assert/strict";
import { lookupMatches, suggestWords } from "./segment.ts";

// The same cases as mobile/test/segment_test.dart.

test("a noun followed by a particle is suggested alone", () => {
  assert.deepEqual(suggestWords(["日本語を勉強します"]), ["日本語", "勉強します"]);
});
test("a verb keeps its ending for the lookup to resolve", () => {
  assert.deepEqual(suggestWords(["昨日寿司を食べました。"]), ["昨日寿司", "食べました"]);
});
test("the ending stops at the next particle", () => {
  assert.deepEqual(suggestWords(["高くても買う"]), ["高くて", "買う"]);
});
test("katakana words of two or more characters, long marks included", () => {
  assert.deepEqual(suggestWords(["コーヒーとケーキ、ア"]), ["コーヒー", "ケーキ"]);
});
test("hiragana-only text and Latin give nothing", () => {
  assert.deepEqual(suggestWords(["とてもおいしい", "Hello 123"]), []);
});
test("と is not taken for a particle, so the lookup has to resolve it", () => {
  assert.deepEqual(suggestWords(["猫と犬"]), ["猫と", "犬"]);
});
test("each word once, across lines, in reading order", () => {
  assert.deepEqual(suggestWords(["猫が好き", "猫も犬"]), ["猫", "好き", "犬"]);
});
test("々 stays inside its word", () => {
  assert.deepEqual(suggestWords(["時々行く"]), ["時々行く"]);
});
test("the ending is capped so a clause is not swallowed", () => {
  assert.deepEqual(suggestWords(["見させられましたよ"]), ["見させられまし"]);
});
test("a lookup counts only if it is the same word", () => {
  assert.equal(lookupMatches("食べました", "食べる"), true);
  assert.equal(lookupMatches("食べました", "飲む"), false);
  assert.equal(lookupMatches("コーヒー", "コーヒー"), true);
  assert.equal(lookupMatches("コーヒー", "コーヒー豆"), false);
  assert.equal(lookupMatches("猫", ""), false);
});
