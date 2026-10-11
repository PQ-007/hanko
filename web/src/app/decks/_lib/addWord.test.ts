import { test } from "node:test";
import assert from "node:assert/strict";
import { autofill, pickedMatch, type AutoKey, type WordFields } from "./addWord.ts";

const empty: WordFields = { term: "生", reading: "", meaning: "", meaningMn: "" };
const sei = { word: "生", reading: "せい", meaning: "life" };
const seikatsu = { word: "生活", reading: "せいかつ", meaning: "living" };

test("empty fields are filled and remembered as machine-filled", () => {
  const r = autofill(empty, new Set(), sei);
  assert.deepEqual(r.fields, { term: "生", reading: "せい", meaning: "life", meaningMn: "" });
  assert.deepEqual([...r.auto].sort(), ["meaning", "meaningMn", "reading"]);
  assert.equal(r.meaningChanged, true);
});

test("a later match replaces what the machine filled — 生 then 活", () => {
  const first = autofill(empty, new Set(), sei);
  const withMn = { ...first.fields, term: "生活", meaningMn: "амьдрал" };
  const r = autofill(withMn, first.auto, seikatsu);
  assert.equal(r.fields.reading, "せいかつ");
  assert.equal(r.fields.meaning, "living");
  // The old Mongolian described the old word: cleared for re-translation.
  assert.equal(r.fields.meaningMn, "");
  assert.equal(r.fields.term, "生活", "the term is never rewritten");
});

test("what the user typed is theirs", () => {
  const typed: WordFields = { term: "生", reading: "なま", meaning: "", meaningMn: "түүхий" };
  const r = autofill(typed, new Set(), sei);
  assert.equal(r.fields.reading, "なま");
  assert.equal(r.fields.meaning, "life");
  assert.equal(r.fields.meaningMn, "түүхий", "a hand-typed Mongolian meaning survives a new English one");
  assert.deepEqual([...r.auto], ["meaning"]);
});

test("the same match again changes nothing and asks for no translation", () => {
  const once = autofill(empty, new Set(), sei);
  const filled = { ...once.fields, meaningMn: "амьдрал" };
  const again = autofill(filled, once.auto as Set<AutoKey>, sei);
  assert.deepEqual(again.fields, filled);
  assert.equal(again.meaningChanged, false);
});

test("the picked match is the one whose word and reading the fields hold", () => {
  const ms = [sei, { word: "生", reading: "なま", meaning: "raw" }];
  assert.equal(pickedMatch({ ...empty, reading: "なま" }, ms), ms[1]);
  assert.equal(pickedMatch({ ...empty, term: " 生 ", reading: "せい" }, ms), ms[0]);
  assert.equal(pickedMatch({ ...empty, reading: "いき" }, ms), null);
});
