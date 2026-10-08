import { test } from "node:test";
import assert from "node:assert/strict";
import { compactGloss, stripNotes } from "./gloss.ts";

// Same cases as mobile/test/dictionary_test.dart `compactGloss`. The
// Mongolian inputs are real Google outputs for Jisho meanings.
const cases: [string, string][] = [
  ["болгоомжтой, болгоомжтой, болгоомжтой; болгоомжтой", "болгоомжтой"],
  ["хүүхэд; хүүхэд; залуу", "хүүхэд, залуу"],
  ["идэх; амьдрах (жишээ нь цалин); амьдрах", "идэх, амьдрах"],
  ["хариуцах, хариуцах; (ажил) хийх", "хариуцах, хийх"],
  [
    "мөрөн дээрээ авч явах; үүрэх, мөрөн дээрээ тавих; хариуцлага хүлээх",
    "мөрөн дээрээ авч явах, үүрэх",
  ],
  ["нэг, хоёр, гурав, дөрөв", "нэг, хоёр, гурав"],
  ["муур", "муур"],
  [
    "to carry on one's shoulder; to bear, to shoulder; to take responsibility",
    "to carry on one's shoulder, to bear",
  ],
  ["child; kid, Child; youngster", "child, kid, youngster"],
  ["to eat; to live on (e.g. a salary); to live off", "to eat, to live on, to live off"],
  [" ; , ", ""],
];

for (const [input, want] of cases) {
  test(`compactGloss: ${input}`, () => {
    assert.equal(compactGloss(input), want);
  });
}

test("stripNotes", () => {
  assert.equal(stripNotes("to live on (e.g. a salary)"), "to live on");
});
