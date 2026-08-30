import { test } from "node:test";
import assert from "node:assert/strict";
import {
  attackChain,
  attackPose,
  critPose,
  CHARACTER_NAMES,
  MAX_ATTACK_TIER,
  SPRITES,
  SPRITE_OFFSET,
} from "./sprites.ts";
import { MONSTER_ROSTER, PLAYER_ROSTER } from "./monsters.ts";

// FighterSprite falls back to `idle` for any pose a character does not have,
// so asking for a missing clip does not error — the swing simply vanishes.
// That is how a Priest crit used to play no attack at all. Everything here
// guards resolution against the real metadata.

test("attackChain is ordered lightest to heaviest and never empty", () => {
  for (const slug of Object.keys(SPRITES)) {
    const chain = attackChain(slug);
    assert.ok(chain.length > 0, `${slug} has no attack`);
    assert.deepEqual([...chain].sort(), chain, `${slug} chain out of order`);
    for (const pose of chain) {
      assert.ok(SPRITES[slug][pose], `${slug} chain names a clip it lacks: ${pose}`);
    }
  }
});

test("every tier resolves to a clip the character actually has", () => {
  for (const slug of Object.keys(SPRITES)) {
    for (let tier = -1; tier <= MAX_ATTACK_TIER + 1; tier++) {
      const pose = attackPose(slug, tier);
      assert.ok(SPRITES[slug][pose], `${slug} tier ${tier} -> missing ${pose}`);
    }
  }
});

test("the Priest, with one attack, never escalates past it", () => {
  assert.deepEqual(attackChain("priest"), ["attack01"]);
  assert.equal(critPose("priest"), "attack01");
});

test("critPose is the heaviest clip on the sheet", () => {
  for (const slug of Object.keys(SPRITES)) {
    const chain = attackChain(slug);
    assert.equal(critPose(slug), chain[chain.length - 1]);
  }
});

test("an unknown slug still yields a usable pose rather than undefined", () => {
  assert.equal(attackPose("not-a-character", 2), "attack01");
});

test("every rostered character has metadata, a name and an offset", () => {
  for (const slug of [...PLAYER_ROSTER, ...MONSTER_ROSTER]) {
    assert.ok(SPRITES[slug], `${slug} has no sprite metadata`);
    assert.ok(SPRITES[slug].idle, `${slug} has no idle clip`);
    assert.ok(CHARACTER_NAMES[slug], `${slug} has no display name`);
    assert.ok(SPRITE_OFFSET[slug], `${slug} has no centring offset`);
  }
});

test("centring offsets stay inside the frame", () => {
  // These are measured corrections in frame pixels; anything large means the
  // generator read the wrong sheet.
  for (const [slug, o] of Object.entries(SPRITE_OFFSET)) {
    assert.ok(Math.abs(o.x) <= 25, `${slug} x offset ${o.x} is implausible`);
    assert.ok(Math.abs(o.y) <= 25, `${slug} y offset ${o.y} is implausible`);
  }
});

test("frame counts are positive integers", () => {
  for (const [slug, states] of Object.entries(SPRITES)) {
    for (const [state, meta] of Object.entries(states)) {
      assert.ok(
        Number.isInteger(meta.frames) && meta.frames > 0,
        `${slug}/${state} has ${meta.frames} frames`
      );
    }
  }
});
