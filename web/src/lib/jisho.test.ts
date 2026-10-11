import { test } from "node:test";
import assert from "node:assert/strict";
import { parseJisho, parseJishoResults } from "./jisho.ts";

// Same cases as parseJisho's tests in mobile/test/dictionary_test.dart: Jisho
// lists an entry under its common spelling, so searching 附属 returns the 付属
// entry with 附属 as an alternative writing.
const variant = {
  data: [
    {
      slug: "付属",
      japanese: [
        { word: "付属", reading: "ふぞく" },
        { word: "附属", reading: "ふぞく" },
      ],
      senses: [{ english_definitions: ["attached"] }],
    },
    {
      slug: "籠る",
      japanese: [
        { word: "篭る", reading: "こもる" },
        { word: "籠る", reading: "こもる" },
      ],
      senses: [{ english_definitions: ["to shut oneself in"] }],
    },
  ],
};

test("the kanji as typed is kept when it's one of the entry's writings", () => {
  assert.deepEqual(parseJisho(variant, "附属"), { word: "附属", reading: "ふぞく", meaning: "attached" });
});

test("a later entry that has the typed writing wins over the first", () => {
  const r = parseJisho(variant, "籠る");
  assert.equal(r.word, "籠る");
  assert.equal(r.meaning, "to shut oneself in");
});

test("a form no entry lists (conjugated) still gets the dictionary form", () => {
  assert.equal(parseJisho(variant, "付属します").word, "付属");
  assert.equal(parseJisho(variant).word, "付属");
});

test("no results or a malformed body is empty", () => {
  assert.deepEqual(parseJisho({ data: [] }), { word: "", reading: "", meaning: "" });
  assert.deepEqual(parseJisho(null), { word: "", reading: "", meaning: "" });
});

test("several results start with parseJisho's pick, then the rest without repeats", () => {
  const rs = parseJishoResults(variant, "籠る");
  assert.deepEqual(rs[0], parseJisho(variant, "籠る"));
  assert.deepEqual(
    rs.map((r) => r.word),
    ["籠る", "付属"]
  );
  assert.deepEqual(parseJishoResults(variant, "籠る", 1).length, 1);
});

test("several results: an entry listing the typed writing shows it, not its main one", () => {
  const twice = { data: [...variant.data, variant.data[1]] };
  assert.deepEqual(
    parseJishoResults(twice, "籠る").map((r) => r.word),
    ["籠る", "付属"]
  );
  assert.deepEqual(parseJishoResults(twice).map((r) => r.word), ["付属", "篭る"]);
});

test("several results of nothing is an empty list", () => {
  assert.deepEqual(parseJishoResults({ data: [] }, "x"), []);
  assert.deepEqual(parseJishoResults(null), []);
});
