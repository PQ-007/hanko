import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { battleOutcome, deriveBattleState, rollEvent, streakTier, type BattleState } from "./damage.ts";
import { buildQuiz } from "./quiz.ts";

// fixtures/battle.fixture.json is what the Flutter port of Monster Hunt is
// tested against (mobile/test/battle_rules_test.dart). This re-runs every
// recorded input through the TypeScript and requires the recorded output, so
// a rule can't change here without the fixture — and therefore the Dart —
// being made to agree. If this fails, decide which side is right; don't just
// regenerate (see the generator's header).

const fixture = JSON.parse(
  await readFile(new URL("./fixtures/battle.fixture.json", import.meta.url), "utf8")
);

function withRandoms<T>(values: number[], fn: () => T): T {
  const real = Math.random;
  let i = 0;
  Math.random = () => values[i++ % values.length];
  try {
    return fn();
  } finally {
    Math.random = real;
  }
}

test("rollEvent matches every recorded roll", () => {
  for (const c of fixture.roll) {
    const before = { streak: c.streak, armorCharges: c.armorCharges } as BattleState;
    const out = withRandoms([c.random], () => rollEvent(c.rating, before, c.timedOut));
    assert.deepEqual(out, c.out, JSON.stringify(c));
  }
});

test("deriveBattleState and battleOutcome match every recorded fight", () => {
  for (const c of fixture.derive) {
    const out = deriveBattleState(c.events, c.monsterStartIndex);
    assert.deepEqual(out, c.out);
    assert.equal(battleOutcome(out, true), c.outcomeQueueEmpty);
    assert.equal(battleOutcome(out, false), c.outcomeQueueLive);
  }
});

test("streakTier matches", () => {
  for (const c of fixture.tiers) assert.equal(streakTier(c.streak), c.tier);
});

test("buildQuiz reproduces every recorded question under the same randoms", () => {
  for (const c of fixture.quiz) {
    const out = withRandoms(c.randoms, () => buildQuiz(c.card, c.words));
    assert.deepEqual(out, c.out);
  }
});

test("the monster shuffle bag deals the recorded sequence", async () => {
  for (const [i, c] of fixture.bag.entries()) {
    // Fresh module per case: the bag lives in module state.
    const mod = await import(`./monsters.ts?fixture=${i}`);
    const picks = withRandoms(c.randoms, () =>
      c.picks.map((p: { exclude: string | null }) => mod.pickMonster(p.exclude ?? undefined))
    );
    assert.deepEqual(picks, c.picks.map((p: { out: string }) => p.out));
  }
});
