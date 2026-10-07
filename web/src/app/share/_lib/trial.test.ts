import { test } from "node:test";
import assert from "node:assert/strict";
import { answerTrial, REQUEUE_GAP, shuffled, startTrial, trialCards, undoTrial } from "./trial.ts";

const words = ["一", "二", "三", "四", "五", "六"].map((term) => ({
  term,
  reading: null,
  meaning: term,
  meaning_mn: null,
}));
const terms = (s: { queue: { term: string }[] }) => s.queue.map((c) => c.term).join("");

test("a hit retires the word; a miss brings it back REQUEUE_GAP cards later", () => {
  let s = startTrial(trialCards(words));
  s = answerTrial(s, "good");
  assert.equal(terms(s), "二三四五六");
  s = answerTrial(s, "again");
  assert.equal(REQUEUE_GAP, 3);
  assert.equal(terms(s), "三四五二六");
  assert.equal(s.reviewed, 2);
});

test("a miss near the end goes last; the session always ends", () => {
  let s = startTrial(trialCards(words.slice(0, 2)));
  s = answerTrial(s, "again");
  assert.equal(terms(s), "二一");
  for (let i = 0; i < 10 && s.queue.length; i++) s = answerTrial(s, "good");
  assert.equal(s.queue.length, 0);
  assert.equal(answerTrial(s, "good"), s, "answering an empty queue is a no-op");
});

test("undo restores the queue and the count, one answer at a time", () => {
  const start = startTrial(trialCards(words));
  const a = answerTrial(start, "again");
  const b = answerTrial(a, "good");
  assert.equal(terms(undoTrial(b)), terms(a));
  assert.equal(undoTrial(b).reviewed, 1);
  assert.equal(terms(undoTrial(undoTrial(b))), terms(start));
  assert.equal(undoTrial(start), start);
});

test("ids are unique and local; shuffle keeps every word", () => {
  const cards = trialCards(words);
  assert.equal(new Set(cards.map((c) => c.card_id)).size, words.length);
  assert.equal(new Set(cards.map((c) => c.word_id)).size, words.length);
  const mixed = shuffled(cards, () => 0.5);
  assert.deepEqual(mixed.map((c) => c.term).sort(), cards.map((c) => c.term).sort());
});
