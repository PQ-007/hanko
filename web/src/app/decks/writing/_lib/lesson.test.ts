import { test } from "node:test";
import assert from "node:assert/strict";
import { kanjiInOrder, kanjiOf, kanjiPositions, partialStrokes, planLesson, wordsForKanji } from "./lesson.ts";

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
