import type { Rating } from "@/lib/srs";

// Combat math for Monster Hunt. Every number below is a first-pass tunable
// constant, not a designed system — expect a balance pass after a real
// playtest.
//
// ARCHITECTURE NOTE, worth reading before touching this file: crit/evade are
// random rolls, but the plan (and Phase B's undo-for-free property) requires
// HP to be a *pure* recompute over history, so undo works by just shrinking
// an array. Those two requirements conflict unless the randomness is resolved
// exactly once, at answer time, and the "recompute" step never rolls
// anything — it only folds over already-decided outcomes. That's the whole
// reason this file is split into rollEvent() (impure, call it exactly once
// per real answer) and deriveBattleState() (pure, safe to call from a
// useMemo on every render, including after undo pops the last event).
// Getting this backwards — e.g. re-rolling crit chance inside the derive
// step — would make HP flicker on every unrelated re-render.
//
// Revision note: distractors now come from the player's own word library
// (fast, synchronous, no Jisho round-trip — see quiz.ts), which means there
// is no part-of-speech data left to grade wrong-answer "closeness" against.
// Wrong-pick damage is a flat value now, not close/far-scaled. Separately,
// a 10s Kahoot-style countdown (BattleArena.tsx) now grades correct answers
// into three speed tiers — easy/good/hard — instead of two, so the damage
// scaling below gained a HARD_DAMAGE_MULTIPLIER to match. A timeout with no
// pick is an honest miss: same `again` rating and same flat wrong-pick
// damage as picking badly, just flagged `timedOut` for the UI so "you ran
// out of time" reads differently from "you picked wrong" without meaning
// anything different to the scheduler.

export const PLAYER_MAX_HP = 100;
export const MONSTER_MAX_HP = 100;

const BASE_WRONG_DAMAGE = 15;

const BASE_CORRECT_DAMAGE = 12;
const EASY_DAMAGE_MULTIPLIER = 1.3; // fast (within the first third of the timer)
const HARD_DAMAGE_MULTIPLIER = 0.7; // barely made it before time ran out
const CRIT_DAMAGE_MULTIPLIER = 1.5;

// Streak beyond this many correct-in-a-row starts building crit/evade chance.
export const STREAK_BONUS_THRESHOLD = 2;
const CRIT_CHANCE_PER_STREAK_POINT = 0.05; // +5% per point of streak above the threshold
const EVADE_CHANCE_PER_STREAK_POINT = 0.05;
const MAX_ROLL_CHANCE = 0.5; // cap — a long enough streak should feel powerful, not guaranteed

export const ARMOR_STREAK_INTERVAL = 7; // every 7th correct-in-a-row (7, 14, 21...) grants a charge
const MAX_ARMOR_CHARGES = 1; // the plan says "one armor charge", not a stockpile

export interface BattleEvent {
  rating: Rating;
  timedOut: boolean; // true only for an auto-resolved timeout, not a genuine wrong pick
  crit: boolean; // only meaningful when the pick was correct
  evaded: boolean; // only meaningful when the pick was wrong
  armorConsumed: boolean; // only meaningful when the pick was wrong
  damage: number; // damage actually applied this event, after crit/evade/armor
}

export interface BattleState {
  playerHp: number;
  monsterHp: number;
  streak: number;
  armorCharges: number;
  crit: boolean; // true if the MOST RECENT event in the fold was a crit
  evaded: boolean; // true if the MOST RECENT event was an evaded wrong-pick
  armorConsumed: boolean; // true if the MOST RECENT event was armor-blocked
  playerDefeated: boolean;
  monsterDefeated: boolean;
}

function clampChance(streak: number, perPoint: number): number {
  const bonus = Math.max(0, streak - STREAK_BONUS_THRESHOLD) * perPoint;
  return Math.min(MAX_ROLL_CHANCE, bonus);
}

function correctDamageMultiplier(rating: Rating): number {
  if (rating === "easy") return EASY_DAMAGE_MULTIPLIER;
  if (rating === "hard") return HARD_DAMAGE_MULTIPLIER;
  return 1; // "good" — the middle speed tier, baseline damage
}

// Rolls and resolves ONE answer into a BattleEvent. Call this exactly once,
// at the moment the player picks an option (or the countdown hits zero) —
// never from inside a render or a useMemo. `stateBefore` is this fight's
// derived state from BEFORE this event (i.e., deriveBattleState() over the
// events array as it stood prior to this pick).
export function rollEvent(
  rating: Rating,
  stateBefore: BattleState,
  timedOut = false
): BattleEvent {
  const wasCorrect = rating !== "again";

  if (wasCorrect) {
    const critChance = clampChance(stateBefore.streak, CRIT_CHANCE_PER_STREAK_POINT);
    const crit = Math.random() < critChance;
    const damage = Math.round(
      BASE_CORRECT_DAMAGE * correctDamageMultiplier(rating) * (crit ? CRIT_DAMAGE_MULTIPLIER : 1)
    );
    return { rating, timedOut: false, crit, evaded: false, armorConsumed: false, damage };
  }

  // Wrong pick (or timeout — same rating, same consequence): armor (if any)
  // blocks it entirely before evade is even rolled — a held charge is a
  // guaranteed save, not another chance-based roll on top of one.
  if (stateBefore.armorCharges > 0) {
    return { rating, timedOut, crit: false, evaded: false, armorConsumed: true, damage: 0 };
  }

  const evadeChance = clampChance(stateBefore.streak, EVADE_CHANCE_PER_STREAK_POINT);
  const evaded = Math.random() < evadeChance;
  const damage = evaded ? 0 : BASE_WRONG_DAMAGE;
  return { rating, timedOut, crit: false, evaded, armorConsumed: false, damage };
}

// Pure fold over already-resolved events — never rolls anything, safe to
// call on every render (and after undo pops the last event) via useMemo.
// `monsterStartIndex` is where the CURRENT monster's fight begins in the
// events array: monster HP and monster-facing streak/armor mechanics only
// see events from that point on, so a freshly-spawned monster in a chained
// fight starts at full HP. Player HP and the correct-streak deliberately
// span the WHOLE events array, not just the current monster's slice — a
// gauntlet where health fully refills every time you beat one enemy has no
// real stakes, and a streak shouldn't reset just because the monster in
// front of you changed (only a wrong answer breaks a streak).
export function deriveBattleState(
  events: BattleEvent[],
  monsterStartIndex: number
): BattleState {
  let playerHp = PLAYER_MAX_HP;
  let monsterHp = MONSTER_MAX_HP;
  let streak = 0;
  let armorCharges = 0;
  let lastCrit = false;
  let lastEvaded = false;
  let lastArmorConsumed = false;

  for (let i = 0; i < events.length; i++) {
    const e = events[i];
    const inCurrentFight = i >= monsterStartIndex;
    const wasCorrect = e.rating !== "again";

    if (wasCorrect) {
      streak += 1;
      if (inCurrentFight) monsterHp = Math.max(0, monsterHp - e.damage);
      // Armor is granted off the whole-session streak (matches the plan:
      // "on reaching a 7-streak" — not scoped to the current monster), capped
      // so it can't stockpile past MAX_ARMOR_CHARGES.
      if (streak % ARMOR_STREAK_INTERVAL === 0) {
        armorCharges = Math.min(MAX_ARMOR_CHARGES, armorCharges + 1);
      }
    } else {
      streak = 0;
      if (e.armorConsumed) {
        armorCharges = Math.max(0, armorCharges - 1);
      } else {
        playerHp = Math.max(0, playerHp - e.damage);
      }
    }

    lastCrit = e.crit;
    lastEvaded = e.evaded;
    lastArmorConsumed = e.armorConsumed;
  }

  return {
    playerHp,
    monsterHp,
    streak,
    armorCharges,
    crit: lastCrit,
    evaded: lastEvaded,
    armorConsumed: lastArmorConsumed,
    playerDefeated: playerHp <= 0,
    monsterDefeated: monsterHp <= 0,
  };
}

export type BattleOutcome = "ongoing" | "defeat" | "cleared";

// Resolves which end-state (if any) applies right now.
//
// Note what is NOT here: killing a monster. It used to return "victory" and
// stop the session on an interstitial screen with a "continue" button, which
// broke the flow every few questions. A defeated monster is now a transition,
// not an ending — the next one spawns in place (see BattleArena's auto-spawn
// effect) and the session runs until the player dies or the queue is done.
// `state.monsterDefeated` is still meaningful, it just drives the death pose
// and the spawn rather than a terminal state.
//
// Defeat is checked first, so an answer that both zeroes player HP and empties
// the queue reads as a loss rather than a completion.
export function battleOutcome(
  state: BattleState,
  queueIsEmpty: boolean
): BattleOutcome {
  if (state.playerDefeated) return "defeat";
  if (queueIsEmpty) return "cleared";
  return "ongoing";
}
