import { test } from "node:test";
import assert from "node:assert/strict";
import { parseQuestions, questionFor, quizFor } from "./sharedQuestions.ts";

const good = { term: "猫", reading: "ねこ", options: ["a", "b", "c", "d"], answer: 2 };

test("parses a planned question set", () => {
  assert.deepEqual(parseQuestions([good]), [good]);
});

test("a missing or malformed set is null, so the arena falls back to its own deck", () => {
  assert.equal(parseQuestions(null), null);
  assert.equal(parseQuestions([]), null);
  assert.equal(parseQuestions("x"), null);
  assert.equal(parseQuestions([{ ...good, options: ["a", "b", "c"] }]), null);
  assert.equal(parseQuestions([{ ...good, answer: 4 }]), null);
  assert.equal(parseQuestions([{ ...good, answer: 1.5 }]), null);
  assert.equal(parseQuestions([{ ...good, options: ["a", "b", "c", 4] }]), null);
});

test("a bad question is skipped, the good ones kept", () => {
  const out = parseQuestions([{ term: 1 }, good, null]);
  assert.deepEqual(out, [good]);
});

test("a missing reading is null", () => {
  assert.equal(parseQuestions([{ ...good, reading: undefined }])?.[0].reading, null);
});

test("rounds are 1-based and wrap", () => {
  const qs = [good, { ...good, term: "犬" }];
  assert.equal(questionFor(qs, 1).term, "猫");
  assert.equal(questionFor(qs, 2).term, "犬");
  assert.equal(questionFor(qs, 3).term, "猫");
  assert.equal(questionFor(qs, 0).term, "猫");
});

test("quiz options keep the server's order and mark only the answer", () => {
  const quiz = quizFor(good);
  assert.deepEqual(quiz.map((o) => o.answerText), ["a", "b", "c", "d"]);
  assert.deepEqual(quiz.map((o) => o.correct), [false, false, true, false]);
  assert.equal(new Set(quiz.map((o) => o.term)).size, 4); // distinct React keys
});
