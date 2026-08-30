"use client";

import { useSyncExternalStore } from "react";
import { PLAYER_CHARACTER, PLAYER_ROSTER } from "./monsters";

// Which fighter the player uses. Kept in localStorage rather than on the
// profile: it changes nothing server-side, no other client reads it, and
// putting it in Postgres would mean a migration plus a round trip before the
// arena could draw its first frame. Per-device is the honest scope for it.
//
// Exposed through useSyncExternalStore rather than a useState + useEffect
// read. Both avoid the hydration mismatch that reading localStorage during
// render would cause (the server has none, so it would render a different
// character than the client), but this is the API React provides for exactly
// this shape of problem: getServerSnapshot answers the server and hydration
// passes, getSnapshot answers every render after. It also means the picker on
// the landing page and the sprite in the Monster Hunt card beside it stay in
// step without either knowing the other exists.
const KEY = "hanko.battle.character";

const listeners = new Set<() => void>();

function subscribe(onChange: () => void) {
  listeners.add(onChange);
  // Covers the same character being changed in another tab. The `storage`
  // event deliberately does not fire in the tab that wrote the value, which is
  // why writePlayerCharacter notifies the local listeners itself.
  window.addEventListener("storage", onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener("storage", onChange);
  };
}

export function readPlayerCharacter(): string {
  if (typeof window === "undefined") return PLAYER_CHARACTER;
  let stored: string | null = null;
  try {
    stored = window.localStorage.getItem(KEY);
  } catch {
    // Private-mode Safari and "block site data" both throw on access.
    return PLAYER_CHARACTER;
  }
  // Validated against the roster, not trusted: a slug left behind by a rename
  // would otherwise render as FighterSprite's missing-sprite box for a whole
  // fight. Returning a plain string also keeps getSnapshot stable under
  // Object.is, which useSyncExternalStore requires.
  return stored && (PLAYER_ROSTER as readonly string[]).includes(stored)
    ? stored
    : PLAYER_CHARACTER;
}

export function writePlayerCharacter(slug: string) {
  try {
    window.localStorage.setItem(KEY, slug);
  } catch {
    // A character that doesn't survive a reload is a small loss; a crash in
    // the picker is not. The in-tab notify below still runs, so the UI updates
    // either way.
  }
  for (const l of listeners) l();
}

export function usePlayerCharacter(): string {
  return useSyncExternalStore(subscribe, readPlayerCharacter, () => PLAYER_CHARACTER);
}
