import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { flattenPath, gradeStrokes, kanjiStrokes, kanjiVgFile, parseKanjiVg, type Polyline } from "./strokes.ts";

const svg = (file: string) => readFileSync(new URL(`./fixtures/${file}`, import.meta.url), "utf8");
const KANJI: Record<string, string> = { 食: "kanjivg_098df.svg", 連: "kanjivg_09023.svg" };

// The shared fixture (PVP-style golden file): mobile's grader decided these
// verdicts; this grader, with its own SVG parser, must reach the same ones.
// Regenerating it to make a failure go away would launder a real difference
// between the two apps into a passing test.
test("grades every shared fixture case exactly as the mobile app does", () => {
  const cases = JSON.parse(readFileSync(new URL("./fixtures/strokes.fixture.json", import.meta.url), "utf8")) as {
    kanji: string;
    name: string;
    drawn: Polyline;
    ok: boolean;
    issue: string | null;
    stroke: number | null;
    expectedStroke: number | null;
  }[];
  assert.ok(cases.length >= 16);
  for (const c of cases) {
    const expected = kanjiStrokes(c.kanji, parseKanjiVg(svg(KANJI[c.kanji]))).polylines;
    const g = gradeStrokes(c.drawn as unknown as Polyline[], expected);
    assert.deepEqual(
      [g.ok, g.issue, g.stroke, g.expectedStroke],
      [c.ok, c.issue, c.stroke, c.expectedStroke],
      `${c.kanji} ${c.name}`
    );
  }
});

test("KanjiVG: strokes in order, nothing but strokes (食 has 9, 連 has 10)", () => {
  assert.equal(parseKanjiVg(svg(KANJI["食"])).length, 9);
  assert.equal(parseKanjiVg(svg(KANJI["連"])).length, 10);
  assert.equal(kanjiVgFile("食"), "098df.svg");
});

test("a real stroke flattens to where it should be", () => {
  const p = flattenPath("M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93C45,25.34,31.75,41.19,14,51.5");
  assert.deepEqual(p[0], [52.75, 10.5]);
  const last = p[p.length - 1];
  assert.ok(Math.abs(last[0] - 14) < 1e-9 && Math.abs(last[1] - 51.5) < 1e-9);
});

test("implicit linetos, smooth curves and packed numbers", () => {
  assert.deepEqual(flattenPath("M10 10 20 10 l0 10").slice(-1)[0], [20, 20]);
  assert.deepEqual(flattenPath("M0,0l1.5-2.25").slice(-1)[0], [1.5, -2.25]);
  const s = flattenPath("M0,0c10,0,10,10,10,10s0,10,10,10");
  assert.deepEqual(s[s.length - 1], [20, 20]);
});

test("an empty expected stroke is graded, not a crash", () => {
  assert.doesNotThrow(() => gradeStrokes([[[1, 1], [2, 2]]], [[]]));
});
