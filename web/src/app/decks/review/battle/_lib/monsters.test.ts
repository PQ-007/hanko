import { test } from "node:test";
import assert from "node:assert/strict";
import { MONSTER_ROSTER, PLAYER_ROSTER, pickMonster } from "./monsters.ts";

// pickMonster deals from a shuffled bag rather than rolling independently each
// spawn. That change came from a real complaint — "where are the orcs?" — with
// a real cause: four orcs in a 33-strong roster meant a 27% chance of meeting
// none of them in ten kills. Independent draws are random in a way that does
// not feel random, and nothing about a bad streak of draws looks like a bug,
// so this is exactly the sort of property that needs a test rather than eyes.

test("every monster appears before any repeats", () => {
  const seen = new Set<string>();
  for (let i = 0; i < MONSTER_ROSTER.length; i++) seen.add(pickMonster());
  assert.equal(
    seen.size,
    MONSTER_ROSTER.length,
    "one full pass must cover the whole roster"
  );
});

test("no monster is ever drawn twice in a row, including across a reshuffle", () => {
  // The reshuffle is the one place a repeat can slip through: a fresh deck can
  // open with the card the old one closed on.
  let previous: string | null = null;
  for (let i = 0; i < 5000; i++) {
    const next = pickMonster();
    assert.notEqual(next, previous, `repeat at draw ${i}`);
    previous = next;
  }
});

test("the excluded character is never spawned", () => {
  // Three characters are on both rosters, so the player can be wearing the
  // armour of something that could otherwise walk on as the opponent. Two
  // identical sprites facing each other reads as a rendering fault.
  const mine = "black-knight-b";
  for (let i = 0; i < 5000; i++) {
    assert.notEqual(pickMonster(mine), mine);
  }
});

test("excluding one monster does not shrink the pool of the others", () => {
  const mine = "black-knight-b";
  const seen = new Set<string>();
  for (let i = 0; i < 3000; i++) seen.add(pickMonster(mine));
  assert.equal(seen.size, MONSTER_ROSTER.length - 1);
});

test("every playable character is also a real character", () => {
  // A slug that exists in a roster but not on disk renders as FighterSprite's
  // placeholder box for a whole fight, which is worse than a crash.
  for (const slug of PLAYER_ROSTER) {
    assert.match(slug, /^[a-z0-9-]+$/, `${slug} is not a valid folder name`);
  }
  assert.equal(new Set(PLAYER_ROSTER).size, PLAYER_ROSTER.length, "no duplicates");
  assert.equal(new Set(MONSTER_ROSTER).size, MONSTER_ROSTER.length, "no duplicates");
});
