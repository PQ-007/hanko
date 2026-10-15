import { test } from "node:test";
import assert from "node:assert/strict";
import { fillExamples, type FillDeps } from "./fillExamples.ts";
import type { WordExample } from "./exampleStore.ts";

// The same cases as mobile/test/fill_examples_test.dart.

const WORDS = [
  { id: "1", term: "食べる" },
  { id: "2", term: "量子論" },
  { id: "3", term: "飲む" },
  { id: "4", term: "見る" },
];

function deps(over: Partial<FillDeps> = {}) {
  const saved = new Map<string, WordExample>();
  const d: FillDeps = {
    find: async (t) => (t === "量子論" ? null : { ja: `${t}文。`, en: `${t}, sentence` }),
    translate: async (t) => `MN:${t}`,
    save: async (id, e) => {
      saved.set(id, e);
      return true;
    },
    ...over,
  };
  return { d, saved };
}

test("every word gets its own sentence, translated whole; misses are counted", async () => {
  const { d, saved } = deps();
  const r = await fillExamples(WORDS, d);
  assert.deepEqual(r, { added: 3, missing: 1, skipped: 0 });
  assert.deepEqual(saved.get("1"), { ja: "食べる文。", en: "食べる, sentence", mn: "MN:食べる, sentence" });
  assert.equal(saved.has("2"), false);
});

test("a word that got a sentence meanwhile, or a failed save, is skipped — the rest carry on", async () => {
  const { d } = deps({
    save: async (id) => {
      if (id === "3") throw new Error("offline");
      return id !== "4";
    },
  });
  assert.deepEqual(await fillExamples(WORDS, d), { added: 1, missing: 1, skipped: 2 });
});

test("progress reaches the total, one step per word", async () => {
  const seen: number[] = [];
  const { d } = deps({ onProgress: (n, total) => seen.push(n * 10 + total) });
  await fillExamples(WORDS, d);
  assert.deepEqual(seen, [14, 24, 34, 44]);
});

test("cancelling stops before the next word", async () => {
  let asked = 0;
  const { d } = deps({
    find: async (t) => {
      asked++;
      return { ja: `${t}。`, en: "x" };
    },
    cancelled: () => asked >= 2,
  });
  const r = await fillExamples(WORDS, d, 1);
  assert.equal(asked, 2);
  assert.equal(r.added, 2);
});

test("never more than the limit in flight", async () => {
  let live = 0;
  let peak = 0;
  const { d } = deps({
    find: async (t) => {
      peak = Math.max(peak, ++live);
      await new Promise((r) => setTimeout(r, 5));
      live--;
      return { ja: `${t}。`, en: "x" };
    },
  });
  await fillExamples([...WORDS, ...WORDS, ...WORDS], d, 3);
  assert.equal(peak, 3);
});
