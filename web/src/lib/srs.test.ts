// Tests for FSRS-5 preview logic in srs.ts.
//
// These cases pin the preview values shown on rating buttons. They intentionally
// do NOT verify fuzz (server-only) or the exact post-graduation stability for
// subsequent reviews — those are covered by the SQL fixture tests. What matters
// here is that each button shows a plausible, FSRS-derived preview rather than
// SM-2 hard-coded constants.
//
// Run: node --test src/lib/srs.test.ts  (Node 22 strips types natively)

import { strict as assert } from "node:assert";
import { describe, it } from "node:test";
import { previewNext, gradeFor, LEARN_STEPS_MINUTES, RELEARN_STEPS_MINUTES } from "./srs.ts";
import type { PreviewCard } from "./srs.ts";

// ── helpers ──────────────────────────────────────────────────────────────────

function newCard(overrides: Partial<PreviewCard> = {}): PreviewCard {
  return {
    state: "new",
    learning_step: 0,
    interval_days: 0,
    stability: null,
    difficulty: null,
    last_reviewed_at: null,
    ...overrides,
  };
}

function reviewCard(stability: number, difficulty: number, daysSince: number, intervalDays: number): PreviewCard {
  const last = new Date(Date.now() - daysSince * 86_400_000).toISOString();
  return {
    state: "review",
    learning_step: 0,
    interval_days: intervalDays,
    stability,
    difficulty,
    last_reviewed_at: last,
  };
}

// ── New / learning cards ──────────────────────────────────────────────────────

describe("new card previews", () => {
  it("Again → first learn step (1 min)", () => {
    const p = previewNext(newCard(), "again");
    assert.equal(p.unit, "minutes");
    assert.equal(p.value, LEARN_STEPS_MINUTES[0]);
  });

  it("Hard → current step (0 → 1 min)", () => {
    const p = previewNext(newCard({ learning_step: 0 }), "hard");
    assert.equal(p.unit, "minutes");
    assert.equal(p.value, LEARN_STEPS_MINUTES[0]);
  });

  it("Good on step 0 → next step (10 min)", () => {
    const p = previewNext(newCard({ learning_step: 0 }), "good");
    assert.equal(p.unit, "minutes");
    assert.equal(p.value, LEARN_STEPS_MINUTES[1]);
  });

  it("Good on last step → graduates, shows FSRS S_0(Good) interval", () => {
    // step 1 is the last step (array length 2, 0-indexed); next=2 >= length=2 → graduate
    const p = previewNext(newCard({ learning_step: 1 }), "good");
    assert.equal(p.unit, "days");
    // S_0(Good) = W[2] = 3.1262, interval = round(3.1262 * 0.2306) = round(0.72) = 1
    assert.equal(p.value, 1);
  });

  it("Easy → skips steps, shows FSRS S_0(Easy) interval", () => {
    const p = previewNext(newCard(), "easy");
    assert.equal(p.unit, "days");
    // S_0(Easy) = W[3] = 15.4722, interval = round(15.4722 * 0.2306) = round(3.57) = 4
    assert.equal(p.value, 4);
  });
});

// ── Learning (mid-steps) ──────────────────────────────────────────────────────

describe("learning card previews", () => {
  it("Again → back to step 0", () => {
    const card = newCard({ state: "learning", learning_step: 1 });
    const p = previewNext(card, "again");
    assert.equal(p.unit, "minutes");
    assert.equal(p.value, LEARN_STEPS_MINUTES[0]);
  });

  it("Hard on step 1 → repeat step 1 (10 min)", () => {
    const card = newCard({ state: "learning", learning_step: 1 });
    const p = previewNext(card, "hard");
    assert.equal(p.unit, "minutes");
    assert.equal(p.value, LEARN_STEPS_MINUTES[1]);
  });
});

// ── Relearning ────────────────────────────────────────────────────────────────

describe("relearning card previews", () => {
  it("Again → relearn step (10 min)", () => {
    const card: PreviewCard = {
      state: "relearning", learning_step: 0,
      interval_days: 5, stability: 2.5, difficulty: 6,
      last_reviewed_at: null,
    };
    const p = previewNext(card, "again");
    assert.equal(p.unit, "minutes");
    assert.equal(p.value, RELEARN_STEPS_MINUTES[0]);
  });

  it("Good → graduates, interval derived from stability", () => {
    const card: PreviewCard = {
      state: "relearning", learning_step: 0,
      interval_days: 5, stability: 4.0, difficulty: 6,
      last_reviewed_at: null,
    };
    const p = previewNext(card, "good");
    assert.equal(p.unit, "days");
    // interval = round(4.0 * 0.2306) = round(0.9224) = 1
    assert.equal(p.value, 1);
  });
});

// ── Review cards ──────────────────────────────────────────────────────────────

describe("review card previews", () => {
  it("Again → shows relearn step (10 min), not post-lapse interval", () => {
    // Clicking Again on a review card moves it to relearning state immediately;
    // the card is due in RELEARN_STEPS_MINUTES[0], not the eventual post-relearn days.
    const card = reviewCard(50, 5, 11, 11);
    const again = previewNext(card, "again");
    assert.equal(again.unit, "minutes");
    assert.equal(again.value, RELEARN_STEPS_MINUTES[0]);
  });

  it("Easy interval > Good interval > Hard interval", () => {
    const card = reviewCard(30, 5, 7, 7);
    const hard = previewNext(card, "hard");
    const good = previewNext(card, "good");
    const easy = previewNext(card, "easy");
    assert.equal(hard.unit, "days");
    assert.equal(good.unit, "days");
    assert.equal(easy.unit, "days");
    assert.ok(hard.value < good.value, `hard(${hard.value}) < good(${good.value})`);
    assert.ok(good.value < easy.value, `good(${good.value}) < easy(${easy.value})`);
  });

  it("Early review (R near 1) gives smaller interval growth than late review (R < 0.9)", () => {
    // Same card, one reviewed right on time, one reviewed late (double interval elapsed)
    const onTime = reviewCard(20, 5, 4,  4);  // reviewed at scheduled time
    const late   = reviewCard(20, 5, 8,  4);  // reviewed 2× overdue
    const onTimeGood = previewNext(onTime, "good");
    const lateGood   = previewNext(late,  "good");
    // Late review has lower R, so recall stability grows more → longer next interval
    assert.ok(lateGood.value > onTimeGood.value,
      `late(${lateGood.value}) should be > on-time(${onTimeGood.value})`);
  });

  it("Null stability falls back to interval_days / INTERVAL_FACTOR", () => {
    const card: PreviewCard = {
      state: "review", learning_step: 0,
      interval_days: 10, stability: null, difficulty: null,
      last_reviewed_at: new Date(Date.now() - 10 * 86_400_000).toISOString(),
    };
    const good = previewNext(card, "good");
    assert.equal(good.unit, "days");
    assert.ok(good.value >= 1);
  });
});

// ── gradeFor ─────────────────────────────────────────────────────────────────

describe("gradeFor", () => {
  it("new word → 'new'", () => {
    assert.equal(gradeFor({ repetitions: 0, interval_days: 0 }), "new");
  });
  it("interval 1 → F", () => {
    assert.equal(gradeFor({ repetitions: 1, interval_days: 1 }), "F");
  });
  it("interval 6 → D", () => {
    assert.equal(gradeFor({ repetitions: 2, interval_days: 6 }), "D");
  });
  it("interval 21 → C", () => {
    assert.equal(gradeFor({ repetitions: 3, interval_days: 21 }), "C");
  });
  it("interval 60 → B", () => {
    assert.equal(gradeFor({ repetitions: 5, interval_days: 60 }), "B");
  });
  it("interval 61 → A", () => {
    assert.equal(gradeFor({ repetitions: 10, interval_days: 61 }), "A");
  });
});
