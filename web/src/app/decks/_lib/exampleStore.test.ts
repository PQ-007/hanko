import { test } from "node:test";
import assert from "node:assert/strict";
import { ExampleStore, exampleOf, exampleRow, type ExampleDeps } from "./exampleStore.ts";

// The same cases as the controller and row tests in
// mobile/test/word_example_test.dart: change one side, change both.

const EAT = { ja: "りんごを食べる。", en: "I eat an apple, every morning." };

function deps(hit: { ja: string; en: string; furigana?: string } | null, queries: string[] = []): ExampleDeps {
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
  assert.deepEqual(exampleRow({ ja: "a", en: "", mn: " " }), { example_ja: "a", example_en: null, example_mn: null, example_furigana: null });
});

/** What a save of `term` ends up writing: what goes in now, or what lands afterwards. */
async function saved(s: ExampleStore, term: string) {
  const r = s.take(term);
  return r.later ? ((await r.later) ?? r.now) : r.now;
}

/** Lets the store finish what it is fetching. */
async function idle(s: ExampleStore) {
  while (s.get().looking || s.get().translating) await new Promise((r) => setTimeout(r, 0));
}

test("a ready suggestion goes in with the word, translated whole", async () => {
  const s = new ExampleStore(deps(EAT));
  s.suggest("食べる", "食べました");
  await idle(s);
  const r = s.take("食べました");
  assert.equal(r.later, null);
  assert.deepEqual(r.now, { ja: "りんごを食べる。", en: "I eat an apple, every morning.", mn: "MN:I eat an apple, every morning." });
});

test("a save never waits: a sentence still on its way lands afterwards, even once the form is cleared", async () => {
  const s = new ExampleStore(deps(EAT));
  s.suggest("食べる");
  const r = s.take("食べる");
  assert.deepEqual(r.now, { ja: "", en: "", mn: "" });
  assert.ok(r.later);
  s.clear(); // the add dialog resets right after saving
  const e = await r.later;
  assert.deepEqual([e?.ja, e?.mn], ["りんごを食べる。", "MN:I eat an apple, every morning."]);
});

test("nothing on Tatoeba: nothing saved, now or later, and it says so", async () => {
  const s = new ExampleStore(deps(null));
  s.suggest("食べる");
  assert.equal(await s.take("食べる").later, null);
  await idle(s);
  assert.equal(s.get().none, true);
  assert.equal(s.take("食べる").now.ja, "");
});

test("a suggestion for a term the user has typed past is not saved under the new one", async () => {
  const s = new ExampleStore(deps(EAT));
  s.suggest("食べる");
  assert.equal(s.take("飲む").later, null, "still searching");
  await idle(s);
  assert.deepEqual(await saved(s, "飲む"), { ja: "", en: "", mn: "" }, "found");
});

test("what the user typed wins: no later suggestion replaces it", async () => {
  const queries: string[] = [];
  const s = new ExampleStore(deps(EAT, queries));
  s.edit("ja", "自分の文。");
  s.suggest("食べる");
  assert.deepEqual(queries, []);
  assert.equal((await saved(s, "全然違う")).ja, "自分の文。");
});

test("a new term replaces an untouched suggestion", async () => {
  const s = new ExampleStore(deps(EAT));
  s.suggest("食べる");
  await idle(s);
  s.suggest("");
  assert.equal(s.isEmpty, true);
});

test("a saved sentence is kept as the dialog opens; research replaces it", async () => {
  const s = new ExampleStore(deps(EAT), { ja: "古い文。", en: "Old.", mn: "Хуучин." });
  s.suggest("食べる");
  assert.equal((await saved(s, "食べる")).ja, "古い文。");
  s.research("食べる");
  assert.equal((await saved(s, "食べる")).ja, "りんごを食べる。");
});

test("English typed by hand: the sentence goes in whole, once its Mongolian is back", async () => {
  const s = new ExampleStore(deps(null));
  s.edit("ja", "文。");
  s.edit("en", "A sentence.");
  const r = s.take("x");
  assert.equal(r.now.ja, "");
  assert.equal((await r.later)?.mn, "MN:A sentence.");
});

test("furigana: a suggestion's reading is saved with it, and dropped once the sentence is edited", async () => {
  const f = "[私|わたし]は[群|むれ]を[見|み]た。";
  const s = new ExampleStore(deps({ ja: "私は群を見た。", en: "I saw a flock.", furigana: f }));
  s.suggest("群");
  await idle(s);
  assert.equal(s.take("群").now.furigana, f);
  assert.equal(exampleRow(s.value).example_furigana, f);
  s.edit("ja", "私が群を見た。");
  assert.equal(s.value.furigana, undefined);
  assert.equal(exampleRow(s.value).example_furigana, null);
  assert.equal(exampleOf({ example_ja: "私が群を見た。", example_furigana: f })?.furigana, undefined);
});
