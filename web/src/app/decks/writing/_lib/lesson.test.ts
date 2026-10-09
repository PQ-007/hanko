import { test } from "node:test";
import assert from "node:assert/strict";
import { kanjiInOrder, kanjiOf, kanjiPositions, lessonSize, partialStrokes, planLesson, wordsForKanji } from "./lesson.ts";

// The same cases as mobile's lesson_test.dart.
const plan = (terms: string[], learned: string[] = []) =>
  planLesson(terms, new Set(learned)).map((s) => (s.char ? `${s.kind}:${s.char}` : `${s.kind}#${s.wordIndex}`));

test("a new kanji climbs the ladder, then the word is asked whole", () => {
  assert.deepEqual(plan(["連帯"]), [
    "trace:連", "partial:連", "blank:連",
    "trace:帯", "partial:帯", "blank:帯",
    "word#0",
  ]);
});

test("kana are given, only kanji are taught", () => {
  assert.deepEqual(plan(["食べる"]), ["trace:食", "partial:食", "blank:食", "word#0"]);
});

test("learned kanji go straight to their word; taught ones aren't repeated", () => {
  assert.deepEqual(plan(["連帯"], ["連"]), ["trace:帯", "partial:帯", "blank:帯", "word#0"]);
  assert.deepEqual(plan(["連帯"], ["連", "帯"]), ["word#0"]);
  assert.deepEqual(plan(["連帯", "連中"]), [
    "trace:連", "partial:連", "blank:連", "trace:帯", "partial:帯", "blank:帯", "word#0",
    "trace:中", "partial:中", "blank:中", "word#1",
  ]);
});

test("a single-kanji word just taught isn't asked twice; kana-only gives nothing", () => {
  assert.deepEqual(plan(["猫"]), ["trace:猫", "partial:猫", "blank:猫"]);
  assert.deepEqual(plan(["猫"], ["猫"]), ["word#0"]);
  assert.deepEqual(plan(["ありがとう"]), []);
});

test("positions, the partial count, the kanji grid and kanji -> words", () => {
  assert.deepEqual(kanjiPositions("食べ物"), [0, 2]);
  assert.deepEqual(kanjiOf("時々"), ["時", "々"]);
  assert.equal(partialStrokes(9), 4);
  assert.equal(partialStrokes(1), 0);
  assert.deepEqual(kanjiInOrder(["連帯", "連中", "食べる"]), ["連", "帯", "中", "食"]);
  const words = ["連帯", "連中", "中心", "食べる"];
  assert.deepEqual(wordsForKanji(["連", "帯"], words, (w) => w), ["連帯"]);
  assert.deepEqual(wordsForKanji(["中", "食"], words, (w) => w), ["連中", "食べる"]);
});

// lessonSize — same cases as lesson_test.dart.
const pairs = ["学校", "先生", "電車", "会社", "時間", "新聞"];

test("lessonSize: stops before passing 10 new kanji", () => {
  assert.equal(lessonSize(pairs, 0), 5); // 5 × 2 = 10; the 6th would make 12
  assert.equal(lessonSize(pairs, 5), 1); // the rest is the next lesson
});

test("lessonSize: kanji already learned don't count", () => {
  assert.equal(lessonSize(pairs, 0, new Set(["学", "校", "先", "生"])), 6);
});

test("lessonSize: a kanji repeated across words counts once", () => {
  assert.equal(lessonSize(["学校", "学生", "校長"], 0), 3);
});

test("lessonSize: one word over the cap still gets a lesson", () => {
  assert.equal(lessonSize(["一二三四五六七八九十百", "学校"], 0), 1);
});

test("lessonSize: at most 10 words even when nothing is new", () => {
  const terms = Array.from({ length: 12 }, () => "学校");
  assert.equal(lessonSize(terms, 0, new Set(["学", "校"])), 10);
  assert.equal(lessonSize([], 0), 0);
});
