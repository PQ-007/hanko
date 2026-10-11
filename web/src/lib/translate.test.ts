import { test } from "node:test";
import assert from "node:assert/strict";
import { parseTranslation } from "./translate.ts";

// Shapes as the endpoints really answered them (see translate.ts).
test("dict-chrome-ex with sl=auto: [[text, lang]]", () => {
  assert.equal(parseTranslation([["түүхий, боловсруулаагүй, шинэхэн", "en"]]), "түүхий, боловсруулаагүй, шинэхэн");
});

test("dict-chrome-ex with a fixed source: [text]", () => {
  assert.equal(parseTranslation(["суралцах"]), "суралцах");
});

test("gtx: one segment per sentence, joined", () => {
  const gtx = [[["Сайн уу. ", "Hello. ", null], ["Сайн байна уу?", "How are you?", null]], null, "en"];
  assert.equal(parseTranslation(gtx), "Сайн уу. Сайн байна уу?");
  assert.equal(parseTranslation([[["төрсөн өдөр", "birthday", null, null, 3]], null, "en"]), "төрсөн өдөр");
});

test("anything else is empty, not a throw", () => {
  assert.equal(parseTranslation(null), "");
  assert.equal(parseTranslation({}), "");
  assert.equal(parseTranslation([]), "");
  assert.equal(parseTranslation([[]]), "");
  assert.equal(parseTranslation([[["", "x"]]]), "");
});
