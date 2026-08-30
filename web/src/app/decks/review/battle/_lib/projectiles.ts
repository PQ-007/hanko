import type { SpriteState } from "./sprites";

// Travelling projectiles, for the characters whose attack actually leaves
// their hands. Imported from the same two packs as the fighters, from the
// per-character `Arrow/Magic/Cannonball (projectile)` folders that the Phase 0
// asset pass deliberately skipped (see CLAUDE.md's "Open items"): they don't
// fit the per-character pose model sprites.ts is built around, because a
// projectile spawns separately and travels attacker -> target rather than
// being one of the character's own poses.
//
// Keyed by attack pose, not just by character, because the pack names them
// that way and means it: the Wizard's attack01 throws a fat orb and its
// attack02 a small fast bolt, and they are different sheets. That falls out
// nicely, since a crit already plays a different pose (see critPose) — so a
// critical wizard hit fires visibly different ammunition.
//
// Only mappings the file names or the character's identity make unambiguous
// are here. Deliberately left out:
//   - Soldier's Arrow01. The folder exists but the soldier has three attacks
//     and nothing says which one is the bow; guessing would attach an arrow to
//     a sword swing.
//   - The beams (Ghostfire, Eyeball Monster, Black Knight_C) and Lava Slime's
//     spike. Those sheets are 300-700px of full-frame effect — a beam that
//     fills the frame is drawn where it lands, not flown across the screen,
//     and dragging one over the card would read as a bug.
export interface ProjectileMeta {
  frames: number;
}

export const PROJECTILES: Record<string, Partial<Record<SpriteState, ProjectileMeta>>> = {
  "archer": { attack01: { frames: 1 }, attack02: { frames: 1 } },
  "black-knight-b": { attack03: { frames: 1 } },
  "demon-b": { attack01: { frames: 1 } },
  "necromancer": { attack02: { frames: 6 } },
  "priest": { attack01: { frames: 5 } },
  "skeleton-archer": { attack01: { frames: 1 } },
  "warlock": { attack02: { frames: 9 } },
  "wizard": { attack01: { frames: 10 }, attack02: { frames: 7 } },
};

export function projectileFor(
  slug: string,
  state: SpriteState
): ProjectileMeta | null {
  return PROJECTILES[slug]?.[state] ?? null;
}
