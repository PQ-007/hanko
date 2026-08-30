import { test } from "node:test";
import assert from "node:assert/strict";
import {
  battleOutcome,
  deriveBattleState,
  rollEvent,
  streakTier,
  MONSTER_MAX_HP,
  PLAYER_MAX_HP,
  type BattleEvent,
} from "./damage.ts";

// These properties were each verified once with a throwaway script during
// development and then had nothing guarding them. They are the rules the fight
// is actually made of, and every one of them is a silent failure if broken:
// nothing throws when HP stops draining or a streak stops counting.
//
// Runs on `node --test` with no dependency and no build step — damage.ts
// imports only a type, which Node's type stripping erases.

const CORRECT: BattleEvent = {
  rating: "good",
  timedOut: false,
  crit: false,
  evaded: false,
  armorConsumed: false,
  damage: 12,
};
const WRONG: BattleEvent = { ...CORRECT, rating: "again", damage: 15 };

/** Runs `fn` with Math.random pinned, so crit/evade rolls are decidable. */
function withRandom<T>(value: number, fn: () => T): T {
  const real = Math.random;
  Math.random = () => value;
  try {
    return fn();
  } finally {
    Math.random = real;
  }
}

test("player HP only falls on wrong answers", () => {
  const s = deriveBattleState([CORRECT, CORRECT, CORRECT], 0);
  assert.equal(s.playerHp, PLAYER_MAX_HP);
});

test("monster HP only falls on correct answers", () => {
  const s = deriveBattleState([WRONG, WRONG], 0);
  assert.equal(s.monsterHp, MONSTER_MAX_HP);
});

test("HP clamps at zero rather than going negative", () => {
  const s = deriveBattleState(Array(20).fill(WRONG), 0);
  assert.equal(s.playerHp, 0);
  assert.ok(s.playerDefeated);
});

test("monsterStartIndex refills the monster but not the player", () => {
  const events = [CORRECT, CORRECT, WRONG];
  const s = deriveBattleState(events, events.length);
  assert.equal(s.monsterHp, MONSTER_MAX_HP, "fresh monster starts full");
  assert.ok(s.playerHp < PLAYER_MAX_HP, "player carries damage between monsters");
});

test("streak survives a monster change and resets on a wrong answer", () => {
  const events = [CORRECT, CORRECT, CORRECT];
  assert.equal(deriveBattleState(events, 2).streak, 3, "streak spans monsters");
  assert.equal(deriveBattleState([...events, WRONG], 0).streak, 0);
});

test("armour is granted every 7th correct answer and capped at one charge", () => {
  const seven = Array(7).fill(CORRECT);
  assert.equal(deriveBattleState(seven, 0).armorCharges, 1);
  // 14 in a row would grant a second; the cap must hold.
  assert.equal(deriveBattleState(Array(14).fill(CORRECT), 0).armorCharges, 1);
});

test("armour blocks the next wrong answer, then is spent", () => {
  const events = [...Array(7).fill(CORRECT), WRONG];
  const state = deriveBattleState(events.slice(0, 7), 0);
  const blocked = withRandom(0.99, () => rollEvent("again", state, false));
  assert.ok(blocked.armorConsumed, "the charge absorbs the hit");
  assert.equal(blocked.damage, 0, "and it costs nothing");
});

test("a high roll cannot crit and a low roll can", () => {
  const hot = deriveBattleState(Array(6).fill(CORRECT), 0);
  assert.equal(withRandom(0.99, () => rollEvent("good", hot, false)).crit, false);
  assert.equal(withRandom(0.0, () => rollEvent("good", hot, false)).crit, true);
});

test("a crit hits harder than the same rating without one", () => {
  const hot = deriveBattleState(Array(6).fill(CORRECT), 0);
  const plain = withRandom(0.99, () => rollEvent("good", hot, false));
  const crit = withRandom(0.0, () => rollEvent("good", hot, false));
  assert.ok(crit.damage > plain.damage);
});

test("faster ratings hit harder: easy > good > hard", () => {
  const cold = deriveBattleState([], 0);
  const dmg = (r: "easy" | "good" | "hard") =>
    withRandom(0.99, () => rollEvent(r, cold, false)).damage;
  assert.ok(dmg("easy") > dmg("good"), "easy beats good");
  assert.ok(dmg("good") > dmg("hard"), "good beats hard");
});

test("a timeout is an ordinary wrong answer that carries a flag", () => {
  const cold = deriveBattleState([], 0);
  const out = withRandom(0.99, () => rollEvent("again", cold, true));
  assert.equal(out.rating, "again");
  assert.ok(out.timedOut);
  assert.ok(out.damage > 0, "a timeout still costs HP");
});

test("defeat is resolved before a cleared queue", () => {
  const dead = deriveBattleState(Array(20).fill(WRONG), 0);
  assert.equal(battleOutcome(dead, true), "defeat");
});

test("undo reproduces the previous state exactly", () => {
  const events = [CORRECT, WRONG, CORRECT, CORRECT];
  const before = deriveBattleState(events.slice(0, 3), 0);
  const after = deriveBattleState(events, 0);
  // Popping the last event must land back on `before` — this is the whole
  // reason HP is a fold over history instead of a mutable counter.
  assert.deepEqual(deriveBattleState(events.slice(0, -1), 0), before);
  assert.notDeepEqual(after, before);
});

test("streakTier steps at the thresholds the fight already uses", () => {
  assert.deepEqual([0, 1, 2, 3, 4, 6, 7, 20].map(streakTier), [0, 0, 0, 1, 1, 1, 2, 2]);
});
