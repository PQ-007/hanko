// Generates battle.fixture.json: the Monster Hunt rules evaluated by THIS
// TypeScript over a fixed set of inputs, for the Flutter port to be checked
// against (mobile/test/battle_rules_test.dart). Both suites read the same file
// — the web's battle-fixture.test.ts re-runs these inputs through the TS and
// fails if the outputs moved — so the two implementations can't drift apart
// without one side going red.
//
// Run from web/:  node src/app/decks/review/battle/_lib/fixtures/generate-battle-fixture.ts
//
// Regenerate ONLY when a rule is meant to change, then make the Dart agree.
// Regenerating to make a red test go green launders a behaviour change into
// a passing suite (same warning as duel.fixture.json in CLAUDE.md).
//
// Randomness is scripted: Math.random is replaced by a cycling list of values,
// and the Dart side consumes the same list in the same order, so a shuffle or
// a crit roll is reproduced exactly rather than only statistically. Every
// scripted value is in [0, 1), the real Math.random range — a 1.0 would index
// one past the end of a Fisher-Yates swap and splice a hole into the options.

import { writeFileSync } from "node:fs";
import {
  battleOutcome,
  deriveBattleState,
  rollEvent,
  streakTier,
  type BattleEvent,
  type BattleState,
} from "../damage.ts";
import { buildQuiz, type OwnWord } from "../quiz.ts";
import type { Rating } from "../../../../../../lib/srs.ts";

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

// Deterministic generator for building the input set itself (not used by the
// rules under test).
let seed = 1;
function rnd(): number {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x80000000;
}
const pick = <T,>(xs: T[]): T => xs[Math.floor(rnd() * xs.length)];

// ---- rollEvent --------------------------------------------------------------
const ratings: Rating[] = ["again", "hard", "good", "easy"];
const roll: unknown[] = [];
for (const rating of ratings) {
  for (const streak of [0, 1, 2, 3, 5, 8, 12, 30]) {
    for (const armorCharges of [0, 1]) {
      for (const timedOut of rating === "again" ? [false, true] : [false]) {
        for (const random of [0, 0.04, 0.05, 0.1, 0.24, 0.25, 0.5, 0.99]) {
          const before = { streak, armorCharges } as BattleState;
          const out = withRandoms([random], () => rollEvent(rating, before, timedOut));
          roll.push({ rating, streak, armorCharges, timedOut, random, out });
        }
      }
    }
  }
}

// ---- deriveBattleState + battleOutcome --------------------------------------
function randomEvent(): BattleEvent {
  const rating = pick(ratings);
  const correct = rating !== "again";
  const armorConsumed = !correct && rnd() < 0.15;
  const evaded = !correct && !armorConsumed && rnd() < 0.15;
  return {
    rating,
    timedOut: !correct && rnd() < 0.2,
    crit: correct && rnd() < 0.2,
    evaded,
    armorConsumed,
    damage: armorConsumed || evaded ? 0 : correct ? pick([8, 12, 16, 18, 23]) : 15,
  };
}
const derive: unknown[] = [];
for (let c = 0; c < 120; c++) {
  const n = Math.floor(rnd() * 30);
  const events = Array.from({ length: n }, randomEvent);
  const monsterStartIndex = n === 0 ? 0 : Math.floor(rnd() * (n + 1));
  const out = deriveBattleState(events, monsterStartIndex);
  derive.push({
    events,
    monsterStartIndex,
    out,
    outcomeQueueEmpty: battleOutcome(out, true),
    outcomeQueueLive: battleOutcome(out, false),
  });
}

// ---- streakTier -------------------------------------------------------------
const tiers = Array.from({ length: 26 }, (_, s) => ({ streak: s, tier: streakTier(s) }));

// ---- buildQuiz --------------------------------------------------------------
const meanings: [string | null, string | null][] = [
  ["cat", "муур"], ["dog", null], [null, "шувуу"], ["fish", "  "], ["tree", "мод"],
  [null, null], ["  ", "  "], ["river", "гол"], ["mountain", "уул"], ["sun", "нар"],
];
const quiz: unknown[] = [];
for (let c = 0; c < 40; c++) {
  const size = 3 + Math.floor(rnd() * 8);
  const words: OwnWord[] = Array.from({ length: size }, (_, i) => {
    const [meaning, meaning_mn] = pick(meanings);
    return { id: `w${i}`, term: `語${i}`, reading: i % 3 ? `ご${i}` : null, meaning, meaning_mn };
  });
  const target = words[Math.floor(rnd() * words.length)];
  const card = {
    card_id: `c-${target.id}`,
    word_id: target.id,
    term: target.term,
    reading: target.reading,
    meaning: target.meaning,
    meaning_mn: target.meaning_mn,
  };
  const randoms = Array.from({ length: 7 }, () => Math.floor(rnd() * 1000) / 1000);
  // buildQuiz only reads these card fields; the cast stands in for the rest
  // of QueueCard, which it never touches.
  const out = withRandoms(randoms, () => buildQuiz(card as never, words));
  quiz.push({ card, words, randoms, out });
}

// ---- monster shuffle bag ----------------------------------------------------
// monsters.ts keeps its bag in module state, so each case imports a fresh copy
// (a distinct URL is a distinct module instance).
const bag: unknown[] = [];
for (let c = 0; c < 6; c++) {
  const mod = await import(`../monsters.ts?case=${c}`);
  const randoms = Array.from({ length: 11 }, () => Math.floor(rnd() * 1000) / 1000);
  const excludes = [undefined, "black-knight-a", "black-knight-b", undefined, "knight"];
  const picks = withRandoms(randoms, () =>
    Array.from({ length: 70 }, (_, i) => {
      const exclude = excludes[i % excludes.length];
      return { exclude: exclude ?? null, out: mod.pickMonster(exclude) };
    })
  );
  bag.push({ randoms, picks });
}

const url = new URL("./battle.fixture.json", import.meta.url);
writeFileSync(url, JSON.stringify({ roll, derive, tiers, quiz, bag }) + "\n");
console.log(
  `wrote ${roll.length} roll, ${derive.length} derive, ${quiz.length} quiz, ${bag.length} bag cases`
);
