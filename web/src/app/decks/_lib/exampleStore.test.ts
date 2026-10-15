import { test } from "node:test";
import assert from "node:assert/strict";
import { ExampleStore, exampleOf, exampleRow, type ExampleDeps } from "./exampleStore.ts";

// The same cases as the controller and row tests in
// mobile/test/word_example_test.dart: change one side, change both.

const EAT = { ja: "りんごを食べる。", en: "I eat an apple, every morning." };

function deps(hit: { ja: string; en: string } | null, queries: string[] = []): ExampleDeps {
  return {
    find: async (q) => {
      queries.push(q);
      return hit;
    },
    translate: async (t) => `MN:${t}`,
  };
}

test("rows: no sentence is no example; parts come back trimmed", () => {
  assert.equal(exampleOf({}), null);
  assert.equal(exampleOf({ example_ja: "  ", example_en: "x" }), null);
  assert.deepEqual(exampleOf({ example_ja: " 食べる。 ", example_en: "Eat." }), { ja: "食べる。", en: "Eat.", mn: "" });
});

test("rows: empty parts are written as null, so clearing really clears", () => {
  assert.deepEqual(exampleRow({ ja: "a", en: "", mn: " " }), { example_ja: "a", example_en: null, example_mn: null });
});

test("a suggestion fills the sentence and translates it whole", async () => {
  const s = new ExampleStore(deps(EAT));
  s.suggest("食べる", "食べました");
  const e = await s.settle("食べました");
  assert.equal(e.ja, "りんごを食べる。");
  assert.equal(e.en, "I eat an apple, every morning.");
  assert.equal(e.mn, "MN:I eat an apple, every morning.");
});

test("nothing on Tatoeba: empty, and says so", async () => {
  const s = new ExampleStore(deps(null));
  s.suggest("食べる");
  assert.equal(s.isEmpty, true);
  await s.settle("食べる");
  assert.equal(s.get().none, true);
});

test("a suggestion for a term the user has typed past is not saved under the new one", async () => {
  const s = new ExampleStore(deps(EAT));
  s.suggest("食べる");
  await s.settle("食べる");
  assert.deepEqual(await s.settle("飲む"), { ja: "", en: "", mn: "" });
});

test("what the user typed wins: no later suggestion replaces it", async () => {
  const queries: string[] = [];
  const s = new ExampleStore(deps(EAT, queries));
  s.edit("ja", "自分の文。");
  s.suggest("食べる");
  assert.deepEqual(queries, []);
  assert.equal((await s.settle("全然違う")).ja, "自分の文。");
});

test("a new term replaces an untouched suggestion", async () => {
  const s = new ExampleStore(deps(EAT));
  s.suggest("食べる");
  await s.settle("食べる");
  s.suggest("");
  assert.equal(s.isEmpty, true);
});

test("a saved sentence is kept as the dialog opens; research replaces it", async () => {
  const s = new ExampleStore(deps(EAT), { ja: "古い文。", en: "Old.", mn: "Хуучин." });
  s.suggest("食べる");
  assert.equal((await s.settle("食べる")).ja, "古い文。");
  s.research("食べる");
  assert.equal((await s.settle("食べる")).ja, "りんごを食べる。");
});

test("English typed by hand gets its Mongolian on save", async () => {
  const s = new ExampleStore(deps(null));
  s.edit("ja", "文。");
  s.edit("en", "A sentence.");
  assert.equal((await s.settle("x")).mn, "MN:A sentence.");
});
