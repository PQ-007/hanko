import { test } from "node:test";
import assert from "node:assert/strict";
import { wrapLines } from "./storyCard.ts";

// One unit per character: width 10 = ten characters per line.
const m = (s: string) => [...s].length;

test("short text stays on one line", () => {
  assert.deepEqual(wrapLines(m, "идэх", 10, 2), ["идэх"]);
});

test("breaks at spaces and keeps every word when it fits", () => {
  assert.deepEqual(wrapLines(m, "нууц, маш нууц мэдээлэл", 10, 3), ["нууц, маш", "нууц", "мэдээлэл"]);
});

test("too long for the lines allowed: the last line ends in an ellipsis", () => {
  const lines = wrapLines(m, "нууц, маш нууц мэдээлэл, далд", 10, 2);
  assert.equal(lines.length, 2);
  assert.equal(lines[0], "нууц, маш");
  assert.ok(lines[1].endsWith("…"));
  assert.ok(m(lines[1]) <= 10);
});

test("a single word longer than a line is split inside the word", () => {
  assert.deepEqual(wrapLines(m, "агааржуулалтынхан", 10, 2), ["агааржуула", "лтынхан"]);
  const cut = wrapLines(m, "агааржуулалтынхантай холбоотой", 10, 2);
  assert.equal(cut.length, 2);
  assert.ok(cut[1].endsWith("…"));
});

test("empty text gives no lines", () => {
  assert.deepEqual(wrapLines(m, "   ", 10, 2), []);
});
