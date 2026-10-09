import { test } from "node:test";
import assert from "node:assert/strict";
import { buildStoryQuiz, wrapLines, type StoryWord } from "./storyCard.ts";

// One unit per character: width 10 = ten characters per line.
const m = (s: string) => [...s].length;

test("short text stays on one line", () => {
  assert.deepEqual(wrapLines(m, "идэх", 10, 2), ["идэх"]);
});

test("breaks at spaces and keeps every word when it fits", () => {
  assert.deepEqual(wrapLines(m, "нууц, маш нууц мэдээлэл", 10, 3), ["нууц, маш", "нууц", "мэдээлэл"]);
});

test("too long for the lines allowed: the last line ends in an ellipsis", () => {
  const lines = wrapLines(m, "нууц, маш нууц мэдээлэл, далд", 10, 2);
  assert.equal(lines.length, 2);
  assert.equal(lines[0], "нууц, маш");
  assert.ok(lines[1].endsWith("…"));
  assert.ok(m(lines[1]) <= 10);
});

test("a single word longer than a line is split inside the word", () => {
  assert.deepEqual(wrapLines(m, "агааржуулалтынхан", 10, 2), ["агааржуула", "лтынхан"]);
  const cut = wrapLines(m, "агааржуулалтынхантай холбоотой", 10, 2);
  assert.equal(cut.length, 2);
  assert.ok(cut[1].endsWith("…"));
});

test("empty text gives no lines", () => {
  assert.deepEqual(wrapLines(m, "   ", 10, 2), []);
});

// buildStoryQuiz — the same cases as mobile's story_card_test.dart.
const w = (term: string, mn: string | null, en: string | null = null): StoryWord => ({ term, reading: null, meaningMn: mn, meaningEn: en });
const five = [w("a", "m1", "e1"), w("b", "m2", "e2"), w("c", "m3", "e3"), w("d", "m4", "e4"), w("e", "m5", "e5")];

test("quiz: word, options and answer slot follow the seed", () => {
  assert.deepEqual(buildStoryQuiz(five, "mn", 0), { word: five[0], options: ["m2", "m1", "m3", "m4"], answer: 1 });
  assert.deepEqual(buildStoryQuiz(five, "mn", 6), { word: five[1], options: ["m3", "m4", "m5", "m2"], answer: 3 });
});

test("quiz: English options when English is asked; Mongolian falls back to English", () => {
  assert.deepEqual(buildStoryQuiz(five, "en", 0)?.options, ["e2", "e1", "e3", "e4"]);
  const mixed = [w("a", null, "e1"), w("b", "m2"), w("c", "m3"), w("d", "m4")];
  assert.deepEqual(buildStoryQuiz(mixed, "mn", 0)?.options, ["m2", "e1", "m3", "m4"]);
});

test("quiz: a repeated meaning is never offered twice", () => {
  const dup = [w("a", "x"), w("b", "x"), w("c", "y"), w("d", "z"), w("e", "v")];
  assert.deepEqual(buildStoryQuiz(dup, "mn", 0)?.options, ["y", "x", "z", "v"]);
});

test("quiz: null without four words of distinct meaning", () => {
  assert.equal(buildStoryQuiz(five.slice(0, 3), "mn", 0), null);
  assert.equal(buildStoryQuiz([w("a", "x"), w("b", "x"), w("c", "x"), w("d", "y"), w("e", "z")], "mn", 0), null);
  assert.equal(buildStoryQuiz([w("a", ""), w("b", "m2"), w("c", "m3"), w("d", "m4")], "mn", 0), null);
});
