import { test } from "node:test";
import assert from "node:assert/strict";
import { buildQuiz, MIN_WORDS_FOR_BATTLE, type OwnWord } from "./quiz.ts";
import type { QueueCard } from "../../../_lib/types.ts";

// The quiz builder decides what a player is asked, so its failures are the
// quiet kind: a question with the answer listed twice, or an option nobody can
// read, still renders perfectly.

function word(id: string, term: string, meaning: string | null, mn?: string | null): OwnWord {
  return { id, term, reading: null, meaning, meaning_mn: mn ?? null };
}

function cardFor(w: OwnWord): QueueCard {
  return {
    card_id: `c-${w.id}`,
    word_id: w.id,
    deck_id: "d",
    template: "recognition",
    state: "review",
    learning_step: 0,
    due_at: new Date().toISOString(),
    interval_days: 5,
    repetitions: 3,
    ease_factor: 2.5,
    term: w.term,
    reading: w.reading,
    meaning: w.meaning,
    meaning_mn: w.meaning_mn,
    audio_path: null,
  };
}

const POOL: OwnWord[] = [
  word("1", "猫", "cat"),
  word("2", "犬", "dog"),
  word("3", "鳥", "bird"),
  word("4", "魚", "fish"),
  word("5", "木", "tree"),
];

test("exactly one option is correct", () => {
  const opts = buildQuiz(cardFor(POOL[0]), POOL);
  assert.equal(opts.filter((o) => o.correct).length, 1);
});

test("the answer is never also offered as a distractor", () => {
  for (let i = 0; i < 200; i++) {
    const opts = buildQuiz(cardFor(POOL[0]), POOL);
    const texts = opts.map((o) => o.answerText);
    assert.equal(new Set(texts).size, texts.length, "no duplicate option text");
  }
});

test("exclusion is by word id, not by term string", () => {
  // Two rows, same term, different ids — a real possibility since nothing
  // stops the same word being captured into two decks. Excluding by term would
  // wrongly drop the duplicate from the pool; excluding by id keeps it.
  const dupes = [...POOL, word("6", "猫", "feline")];
  const opts = buildQuiz(cardFor(dupes[0]), dupes);
  assert.equal(opts.filter((o) => o.correct).length, 1);
});

test("words with no meaning at all are never offered", () => {
  const thin = [...POOL, word("7", "空", null, null)];
  for (let i = 0; i < 100; i++) {
    for (const o of buildQuiz(cardFor(thin[0]), thin)) {
      assert.ok(o.answerText.trim().length > 0, "blank option offered");
    }
  }
});

test("meaning_mn wins over meaning when both exist", () => {
  const mn = word("8", "本", "book", "ном");
  const opts = buildQuiz(cardFor(mn), [mn, ...POOL]);
  assert.equal(opts.find((o) => o.correct)?.answerText, "ном");
});

test("a pool at the documented minimum still produces a full question", () => {
  const four = POOL.slice(0, MIN_WORDS_FOR_BATTLE);
  assert.equal(buildQuiz(cardFor(four[0]), four).length, MIN_WORDS_FOR_BATTLE);
});

test("a pool below the minimum degrades instead of throwing", () => {
  const two = POOL.slice(0, 2);
  const opts = buildQuiz(cardFor(two[0]), two);
  assert.ok(opts.length >= 1 && opts.length <= 2);
  assert.equal(opts.filter((o) => o.correct).length, 1);
});

test("the correct answer lands in every slot about equally often", () => {
  // The original shuffle was `.sort(() => Math.random() - 0.5)`, which measured
  // 36/17/16/31 across the four slots — enough bias that "always guess slot 0"
  // beats recall. This is the regression that must never come back.
  const runs = 20000;
  const counts = [0, 0, 0, 0];
  for (let i = 0; i < runs; i++) {
    counts[buildQuiz(cardFor(POOL[0]), POOL).findIndex((o) => o.correct)]++;
  }
  for (const [slot, n] of counts.entries()) {
    const pct = (n / runs) * 100;
    assert.ok(pct > 22 && pct < 28, `slot ${slot} at ${pct.toFixed(1)}%, expected ~25%`);
  }
});
