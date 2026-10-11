import { test } from "node:test";
import assert from "node:assert/strict";
import { insertAt, parseCandidates, toGoogleInk } from "./handwriting.ts";

test("ink goes over as rounded [xs, ys, []] per stroke, empty strokes dropped", () => {
  assert.deepEqual(
    toGoogleInk([
      [
        [1.4, 2.6],
        [10, 20.5],
      ],
      [],
      [[3, 4]],
    ]),
    [
      [[1, 10], [3, 21], []],
      [[3], [4], []],
    ]
  );
});

test("candidates come out in order, deduplicated, capped", () => {
  // The shape the endpoint really answered with for a drawn 日.
  const body = ["SUCCESS", [["f0e9d2f4243e795b", ["日", "曰", "日日", "曰日", "日", " "], [], {}]]];
  assert.deepEqual(parseCandidates(body), ["日", "曰", "日日", "曰日"]);
  assert.deepEqual(parseCandidates(body, 2), ["日", "曰"]);
});

test("an error status or an unexpected shape is no candidates, not a throw", () => {
  assert.deepEqual(parseCandidates(["FAILED_TO_PARSE_REQUEST_BODY"]), []);
  assert.deepEqual(parseCandidates(["SUCCESS", []]), []);
  assert.deepEqual(parseCandidates(["SUCCESS", [["id", "日"]]]), []);
  assert.deepEqual(parseCandidates(null), []);
  assert.deepEqual(parseCandidates({}), []);
});

test("a candidate replaces the selection and the caret lands after it", () => {
  assert.deepEqual(insertAt("", 0, 0, "生"), { text: "生", caret: 1 });
  assert.deepEqual(insertAt("生", 1, 1, "活"), { text: "生活", caret: 2 });
  assert.deepEqual(insertAt("生活", 0, 0, "学"), { text: "学生活", caret: 1 });
  assert.deepEqual(insertAt("生x活", 1, 2, "々"), { text: "生々活", caret: 2 });
  // A stale selection past the end appends instead of throwing or padding.
  assert.deepEqual(insertAt("生", 9, 9, "活"), { text: "生活", caret: 2 });
});
