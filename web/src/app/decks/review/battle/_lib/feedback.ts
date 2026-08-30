// Physical feedback for hits. Deliberately tiny and defensive: this is
// decoration, and nothing here may ever throw into the answer path.
//
// Support is genuinely partial — the Vibration API works on Android Chrome
// and Firefox but is absent on all iOS browsers (including Chrome on iOS,
// which is Safari underneath), and desktops have no vibration hardware. So
// this is a bonus on the devices that have it, never something the game's
// feedback depends on: every hit is also shown through the HP bars, the
// sprite pose, the damage number, and the screen shake.
//
// Patterns are short on purpose. Long or frequent buzzing on a review app
// gets annoying fast, and some browsers throttle or ignore repeated calls.

type VibratePattern = number | number[];

function vibrate(pattern: VibratePattern) {
  if (typeof navigator === "undefined") return;
  const nav = navigator as Navigator & { vibrate?: (p: VibratePattern) => boolean };
  if (typeof nav.vibrate !== "function") return;
  try {
    nav.vibrate(pattern);
  } catch {
    // Some browsers throw if called without a user gesture or while hidden.
    // A failed buzz is not worth surfacing.
  }
}

/** Landing a normal hit on the monster. */
export function buzzHit() {
  vibrate(18);
}

/** Landing a critical hit — two quick taps so it reads as "bigger". */
export function buzzCrit() {
  vibrate([14, 36, 24]);
}

/** Taking damage: one longer, blunter buzz. */
export function buzzHurt() {
  vibrate(55);
}

/** A blocked or evaded hit — a light tick, distinct from taking damage. */
export function buzzDeflect() {
  vibrate(10);
}

/** Killing a monster — the longest pattern here, because it's the rarest. */
export function buzzVictory() {
  vibrate([28, 40, 28, 40, 60]);
}
