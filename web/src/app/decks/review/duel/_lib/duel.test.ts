import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DUEL_MAX_HP,
  DUEL_ROUND_COUNT,
  FALLBACK_BASELINE_MS,
  INITIAL_DUEL_STATE,
  deriveDuelState,
  duelOutcome,
  duelStreakTier,
  resolveRound,
  roundDamage,
  roundDurationMs,
  speedRatio,
  type DuelState,
  type ResolvedRound,
} from "./duel.ts";

// ---------------------------------------------------------------------------
// Round timing
// ---------------------------------------------------------------------------

test("the round timer tightens from 5s to a 3s floor", () => {
  assert.equal(roundDurationMs(1), 5000);
  assert.ok(roundDurationMs(5) < roundDurationMs(1));
  assert.equal(roundDurationMs(9), 3000);
});

test("the timer never drops below the floor, however long the match", () => {
  for (const n of [9, 12, 40, 500]) {
    assert.equal(roundDurationMs(n), 3000, `round ${n}`);
  }
});

test("round numbering is 1-based and round 0 does not shorten the timer", () => {
  // Guards an off-by-one that would silently hand round 1 a 4.75s timer.
  assert.equal(roundDurationMs(0), 5000);
});

// ---------------------------------------------------------------------------
// Speed ratio — the fairness mechanism
// ---------------------------------------------------------------------------

test("answering at exactly your own baseline is a ratio of 1", () => {
  assert.equal(speedRatio(4000, 4000), 1);
});

test("the ratio clamps at both ends", () => {
  // Impossibly fast and impossibly slow both saturate rather than running away.
  assert.equal(speedRatio(1, 60_000), 1.6);
  assert.equal(speedRatio(60_000, 1000), 0.6);
});

test("a null baseline falls back to the constant, not to zero or NaN", () => {
  // response_baseline() returns null below its sample floor. If that fell
  // through as 0 the ratio would be 0/elapsed = 0 and every hit would be
  // clamped to the minimum — a new account would deal 60% damage forever.
  assert.equal(speedRatio(FALLBACK_BASELINE_MS, null), 1);
  assert.equal(speedRatio(FALLBACK_BASELINE_MS, 0), 1);
});

test("two players at their own baselines deal identical damage at different speeds", () => {
  // The entire point of scaling against a personal median: a habitual 2s
  // answerer must not out-damage a 6s answerer simply for being quick.
  const fast = roundDamage({ correct: true, elapsedMs: 2000 }, 2000, 0);
  const slow = roundDamage({ correct: true, elapsedMs: 6000 }, 6000, 0);
  assert.equal(fast, slow);
});

// ---------------------------------------------------------------------------
// Damage
// ---------------------------------------------------------------------------

test("a wrong answer and a timeout both deal nothing, and neither self-penalises", () => {
  assert.equal(roundDamage({ correct: false, elapsedMs: 900 }, 4000, 5), 0);
  assert.equal(roundDamage(null, 4000, 5), 0);
});

test("streak tiers step at 3 and 6", () => {
  assert.equal(duelStreakTier(0), 0);
  assert.equal(duelStreakTier(2), 0);
  assert.equal(duelStreakTier(3), 1);
  assert.equal(duelStreakTier(5), 1);
  assert.equal(duelStreakTier(6), 2);
  assert.equal(duelStreakTier(30), 2);
});

test("a longer streak strictly increases damage for the same answer", () => {
  const answer = { correct: true, elapsedMs: 4000 };
  const none = roundDamage(answer, 4000, 0);
  const tier1 = roundDamage(answer, 4000, 3);
  const tier2 = roundDamage(answer, 4000, 6);
  assert.ok(tier1 > none, `${tier1} > ${none}`);
  assert.ok(tier2 > tier1, `${tier2} > ${tier1}`);
});

test("damage is deterministic — the same inputs always give the same number", () => {
  // Load-bearing from PVP.md phase 3 on: Postgres becomes authoritative and
  // the client renders what it returns. A crit roll here would put the two
  // in permanent disagreement by design.
  const args = [{ correct: true, elapsedMs: 2200 }, 3800, 4] as const;
  const first = roundDamage(...args);
  for (let i = 0; i < 50; i++) assert.equal(roundDamage(...args), first);
});

test("a flawless match lands near a kill without trivially overshooting it", () => {
  // The balance claim in duel.ts's header, pinned. If someone retunes the
  // constants so twelve perfect rounds end the match at round five, this is
  // the test that says so.
  let state = INITIAL_DUEL_STATE;
  const rounds: ResolvedRound[] = [];
  for (let n = 1; n <= DUEL_ROUND_COUNT; n++) {
    const r = resolveRound(n, { correct: true, elapsedMs: 4000 }, null, 4000, null, state);
    rounds.push(r);
    state = deriveDuelState(rounds);
  }
  assert.ok(state.theirHp <= 0, "a flawless run should win");
  // But not so hard that the match was over less than half way through.
  const halfway = deriveDuelState(rounds.slice(0, DUEL_ROUND_COUNT / 2));
  assert.ok(halfway.theirHp > 0, `still standing at the half: ${halfway.theirHp}`);
});

// ---------------------------------------------------------------------------
// The fold
// ---------------------------------------------------------------------------

test("damage lands on the other side, not on the dealer", () => {
  const state = deriveDuelState([
    { roundNo: 1, you: { correct: true, elapsedMs: 1000 }, them: null, yourDamage: 12, theirDamage: 0 },
  ]);
  assert.equal(state.yourHp, DUEL_MAX_HP);
  assert.equal(state.theirHp, DUEL_MAX_HP - 12);
});

test("HP floors at zero rather than going negative", () => {
  const state = deriveDuelState([
    { roundNo: 1, you: null, them: { correct: true, elapsedMs: 900 }, yourDamage: 0, theirDamage: 500 },
  ]);
  assert.equal(state.yourHp, 0);
});

test("a wrong answer resets that player's streak and only that player's", () => {
  const state = deriveDuelState([
    { roundNo: 1, you: { correct: true, elapsedMs: 1000 }, them: { correct: true, elapsedMs: 1000 }, yourDamage: 8, theirDamage: 8 },
    { roundNo: 2, you: { correct: false, elapsedMs: 1000 }, them: { correct: true, elapsedMs: 1000 }, yourDamage: 0, theirDamage: 8 },
  ]);
  assert.equal(state.yourStreak, 0);
  assert.equal(state.theirStreak, 2);
});

test("a timeout breaks the streak exactly like a wrong answer", () => {
  const state = deriveDuelState([
    { roundNo: 1, you: { correct: true, elapsedMs: 1000 }, them: null, yourDamage: 8, theirDamage: 0 },
    { roundNo: 2, you: null, them: null, yourDamage: 0, theirDamage: 0 },
  ]);
  assert.equal(state.yourStreak, 0);
});

test("the fold is pure — folding twice gives the same state", () => {
  // deriveDuelState runs from a useMemo on every render. If it decided
  // anything, HP would flicker on unrelated re-renders.
  const rounds: ResolvedRound[] = [
    { roundNo: 1, you: { correct: true, elapsedMs: 1200 }, them: { correct: false, elapsedMs: 2000 }, yourDamage: 11, theirDamage: 0 },
    { roundNo: 2, you: { correct: true, elapsedMs: 900 }, them: { correct: true, elapsedMs: 1500 }, yourDamage: 13, theirDamage: 9 },
  ];
  assert.deepEqual(deriveDuelState(rounds), deriveDuelState(rounds));
});

test("dropping the last round reproduces the earlier state exactly", () => {
  const rounds: ResolvedRound[] = [
    { roundNo: 1, you: { correct: true, elapsedMs: 1200 }, them: null, yourDamage: 11, theirDamage: 0 },
    { roundNo: 2, you: { correct: false, elapsedMs: 900 }, them: { correct: true, elapsedMs: 1500 }, yourDamage: 0, theirDamage: 9 },
  ];
  assert.deepEqual(deriveDuelState(rounds.slice(0, 1)), deriveDuelState([rounds[0]]));
});

// ---------------------------------------------------------------------------
// Outcomes
// ---------------------------------------------------------------------------

function stateWith(over: Partial<DuelState>): DuelState {
  return { ...INITIAL_DUEL_STATE, ...over };
}

test("an unfinished match with both sides standing is ongoing", () => {
  assert.equal(duelOutcome(stateWith({ roundsPlayed: 4, yourHp: 60, theirHp: 40 })), "ongoing");
});

test("zeroing the opponent wins, being zeroed loses", () => {
  assert.equal(duelOutcome(stateWith({ theirHp: 0, theirDefeated: true })), "won");
  assert.equal(duelOutcome(stateWith({ yourHp: 0, yourDefeated: true })), "lost");
});

test("a simultaneous knockout is a draw, not a loss", () => {
  // Reachable, not theoretical: both sides' damage lands in the same round.
  assert.equal(
    duelOutcome(stateWith({ yourHp: 0, theirHp: 0, yourDefeated: true, theirDefeated: true })),
    "draw"
  );
});

test("running out of rounds decides on remaining HP, and ties draw", () => {
  const done = { roundsPlayed: DUEL_ROUND_COUNT };
  assert.equal(duelOutcome(stateWith({ ...done, yourHp: 30, theirHp: 10 })), "won");
  assert.equal(duelOutcome(stateWith({ ...done, yourHp: 10, theirHp: 30 })), "lost");
  assert.equal(duelOutcome(stateWith({ ...done, yourHp: 22, theirHp: 22 })), "draw");
});

test("a knockout outranks the round count", () => {
  // An answer that both empties the round list and kills must read as a
  // knockout, not as a points decision.
  assert.equal(
    duelOutcome(stateWith({ roundsPlayed: DUEL_ROUND_COUNT, theirHp: 0, theirDefeated: true, yourHp: 5 })),
    "won"
  );
});

// ---------------------------------------------------------------------------
// The golden fixture (PVP.md phase 3.3)
// ---------------------------------------------------------------------------

// duel_damage() in 0020_pvp.sql is a hand-written mirror of roundDamage(). The
// duplication is deliberate — bot matches never touch the network, and PvP
// matches must not trust the client — but it is exactly the "two
// implementations drifting unchecked" hazard CLAUDE.md's Stack section warns
// about. These 484 cases are the shared contract: this test pins the
// TypeScript half, and supabase/tests/duel_damage_fixture.sql pins the SQL
// half against the same file. Change a constant in either and one of the two
// goes red.
//
// Regenerating the fixture is NOT the fix for a failure here — it would
// launder a real behaviour change into a passing test. Change it only when
// the rules are meant to change, and re-run the SQL check in the same breath.
test("roundDamage still agrees with the golden fixture", async () => {
  const { default: fixture } = await import("./duel.fixture.json", {
    with: { type: "json" },
  });
  assert.ok(fixture.length > 400, "fixture should be the full grid");
  for (const c of fixture) {
    const answer = c.correct === null ? null : { correct: c.correct, elapsedMs: c.elapsedMs! };
    assert.equal(
      roundDamage(answer, c.baselineMs, c.streak),
      c.damage,
      `correct=${c.correct} elapsed=${c.elapsedMs} baseline=${c.baselineMs} streak=${c.streak}`
    );
  }
});
