import { test } from "node:test";
import assert from "node:assert/strict";
import { eligibleKinds, pickKind, speedFor, timeLimitFor, WRITE_MS_PER_KANJI } from "./questionKinds.ts";

// Same cases as mobile's question_kinds_test.dart.
const yes = () => true;
const no = () => false;

test("eligibility: kanji words can be written; kana, too-long and unloaded can't", () => {
  assert.deepEqual([...eligibleKinds("連帯", yes)].sort(), ["meaning", "write"]);
  assert.deepEqual([...eligibleKinds("連帯", no)], ["meaning"]);
  assert.deepEqual([...eligibleKinds("ありがとう", yes)], ["meaning"]);
  assert.deepEqual([...eligibleKinds("国際連合", yes)], ["meaning"]);
  assert.deepEqual([...eligibleKinds("連帯", (k) => k === "連")], ["meaning"], "every kanji needs stroke data");
});

test("weights split the range: meaning 3, write 2 (of 5)", () => {
  const all = new Set(["meaning", "write"] as const);
  assert.equal(pickKind(all, () => 0), "meaning");
  assert.equal(pickKind(all, () => 0.59), "meaning");
  assert.equal(pickKind(all, () => 0.61), "write");
  assert.equal(pickKind(all, () => 0.99), "write");
  assert.equal(pickKind(new Set(["meaning"] as const), () => 0.99), "meaning");
});

test("writing time scales with the kanji; speed is judged against it", () => {
  assert.equal(timeLimitFor("write", "連帯"), 2 * WRITE_MS_PER_KANJI);
  assert.equal(timeLimitFor("write", "食べる"), WRITE_MS_PER_KANJI);
  assert.equal(timeLimitFor("meaning", "連帯"), 10_000);
  assert.equal(speedFor(5000, 24000), "easy");
  assert.equal(speedFor(12000, 24000), "good");
  assert.equal(speedFor(20000, 24000), "hard");
});
