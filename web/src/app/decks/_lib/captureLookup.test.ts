import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveCapture } from "./captureLookup.ts";

const jisho: Record<string, { word: string; reading: string; meaning: string }> = {
  食べました: { word: "食べる", reading: "たべる", meaning: "to eat" },
  食べた: { word: "食べる", reading: "たべる", meaning: "to eat" },
  昨日寿司: { word: "昨日", reading: "きのう", meaning: "yesterday" },
  コーヒー: { word: "コーヒー", reading: "コーヒー", meaning: "coffee" },
  量子論: { word: "論", reading: "ろん", meaning: "theory" },
};
const deps = {
  lookup: async (t: string) => jisho[t] ?? null,
  translate: async (t: string) => `MN:${t}`,
};

test("each term to its dictionary form, reading and both meanings", async () => {
  const items = await resolveCapture(["食べました", "コーヒー"], deps);
  assert.deepEqual(items[0], { term: "食べる", reading: "たべる", meaning: "to eat", meaningMn: "MN:to eat", found: true });
  assert.equal(items[1].reading, "", "a katakana word's reading is itself: left blank");
});

test("two forms of one word collapse into one, in the order chosen", async () => {
  const items = await resolveCapture(["食べた", "コーヒー", "食べました"], deps);
  assert.deepEqual(items.map((i) => i.term), ["食べる", "コーヒー"]);
});

test("Jisho's guess at another word, or no answer at all, keeps the term as photographed", async () => {
  const items = await resolveCapture(["量子論", "謎語"], deps);
  assert.deepEqual(items.map((i) => [i.term, i.found, i.meaning]), [
    ["量子論", false, ""],
    ["謎語", false, ""],
  ]);
});

test("a failed lookup is a word to fill in by hand, not an error", async () => {
  const items = await resolveCapture(["食べた"], { ...deps, lookup: async () => Promise.reject(new Error("offline")) });
  assert.deepEqual(items.map((i) => i.found), [false]);
});
