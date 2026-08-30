"use client";

import { useEffect } from "react";
import { LOOP_MS, ONE_SHOT_MS, SPRITE_OFFSET, SPRITES, type SpriteState } from "../_lib/sprites";

// Which pose to show is decided by the parent (BattleArena) — it's the only
// thing that knows an answer just happened and can pose BOTH fighters
// together. What this component owns is when a one-shot pose is *finished*:
// it reports that via onOneShotEnd (driven by the real `animationend` event)
// so the parent can drop straight back to idle.
//
// That callback replaced a fixed 650ms timer in the parent. The timer was
// longer than the 500ms clip, so every attack froze on its last frame for
// ~150ms and then jumped to idle — a visible stutter at exactly the moment
// the hit should have flowed back into the idle loop. `animationend` is
// frame-accurate by construction, so the two clips now abut with no gap and
// no cut-off.
//
// Native 100px sizing (matches the source frames exactly) — display scaling
// is a `transform` from --hanko-fighter-scale, published by the parent
// .hanko-fighter-slot so it can be responsive (globals.css). A pure visual
// transform can't perturb the frame-stepping arithmetic at any value.
//
// The `key` includes `state`: React remounts the element whenever the pose
// changes, which restarts the CSS animation from frame 0. Without that, two
// consecutive identical poses (e.g. two crits in a row, both "attack01")
// would look like the same still-running cycle to the browser and never
// restart.
export default function FighterSprite({
  slug,
  state,
  flip = false,
  preload,
  onOneShotEnd,
}: {
  slug: string;
  state: SpriteState;
  flip?: boolean;
  /**
   * Which clips to warm. Defaults to every clip the character has, which is
   * right in the arena — any pose can come up at any moment. Pass a narrower
   * list where only a few are reachable: the loading scene cycles a new pair
   * of fighters every few seconds, and warming all sixteen sheets for each
   * pair would have it competing for bandwidth with the query it is waiting
   * on, which is precisely backwards.
   */
  preload?: SpriteState[];
  onOneShotEnd?: () => void;
}) {
  const meta = SPRITES[slug];

  // Warm every clip this character can play, as soon as the character is
  // known. Without this the FIRST attack/hurt of a fight paints an empty box
  // while its PNG is still being fetched — and because changing pose remounts
  // the element (see above), that empty frame is very visible. Preloading
  // makes the swap hit a warm cache instead.
  useEffect(() => {
    const all = meta ? (Object.keys(meta) as SpriteState[]) : [];
    const states = preload ? all.filter((s) => preload.includes(s)) : all;
    for (const s of states) {
      const img = new window.Image();
      img.src = `/battle/characters/${slug}/${s}.png`;
    }
    // `preload` is intentionally read but not a dependency: callers pass an
    // array literal, so depending on it would re-run this on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slug, meta]);

  if (!meta) {
    // No sprite data at all for this slug (shouldn't happen with the current
    // 42-character roster, but a missing/renamed slug must never crash the
    // fight) — a plain placeholder box, not a broken image.
    return (
      <div
        style={{ transform: "scale(var(--hanko-fighter-scale, 1))" }}
        className="flex h-[100px] w-[100px] items-center justify-center rounded-control bg-paper-deep text-3xl"
      >
        ❓
      </div>
    );
  }

  // Falls back to idle if this character has no clip for the requested pose
  // (e.g. most characters lack "block") — every character is guaranteed to
  // have at least idle (see sprites.ts's generation notes).
  const resolvedState: SpriteState = meta[state] ? state : "idle";
  const frames = meta[resolvedState]?.frames ?? 1;
  const loop = resolvedState === "idle" || resolvedState === "walk";
  // Short clips (attacks, hurt) play faster than the idle loop — a 6-frame
  // idle at attack speed would read as jittery rather than calm. The numbers
  // live in sprites.ts because BattleArena times projectile launches against
  // them (see ONE_SHOT_MS).
  const durationMs = loop ? LOOP_MS : ONE_SHOT_MS;

  // Read right to left: the character is first nudged to the centre of its own
  // frame (see SPRITE_OFFSET — nobody is drawn centred in these packs), then
  // scaled, then mirrored if it faces left.
  //
  // The order is what makes the offset correct rather than merely applied.
  // Putting translate last means it happens in the element's own coordinates,
  // so the scale multiplies it — the nudge grows with the sprite instead of
  // staying a fixed handful of screen pixels. And the mirror lands on the
  // already-offset result, which is exactly right: a flipped character's
  // content sits mirrored in its frame too, so its correction has to flip with
  // it. scaleX(-1) does that for free.
  //
  // None of this touches the frame-stepping arithmetic: that runs on
  // background-position, which a transform can't perturb at any value.
  const offset = SPRITE_OFFSET[slug] ?? { x: 0, y: 0 };
  const transform =
    `${flip ? "scaleX(-1) " : ""}scale(var(--hanko-fighter-scale, 1)) ` +
    `translate(${offset.x}px, ${offset.y}px)`;

  return (
    <div
      key={resolvedState}
      // shrink-0 is load-bearing, not tidiness. This is a flex item wherever
      // it's used, and the hero-picker chips are narrower than 100px — so the
      // element was being squeezed to fit (79px at sm, 60px on mobile) while
      // the background stayed anchored at x=0. Frame-x 50 then rendered 50px
      // from a left edge whose box was only 79px wide, putting the character
      // ~10px right of centre before scaling, ~16px after. The frame-stepping
      // arithmetic assumes a 100px window; nothing may resize it.
      className="hanko-sprite h-[100px] w-[100px] shrink-0"
      // Never fires for idle/walk (they're infinite), so the guard is really
      // just documentation — but it keeps the contract explicit.
      onAnimationEnd={loop ? undefined : onOneShotEnd}
      style={
        {
          backgroundImage: `url(/battle/characters/${slug}/${resolvedState}.png)`,
          transform,
          "--hanko-frames": frames,
          "--hanko-frame-w": `${frames * 100}px`,
          // -(frames-1), not -frames: the animation must END on the last real
          // frame rather than one step past the sheet. See globals.css for
          // the full jump-none derivation — the old value made every one-shot
          // hold a blank frame at the end.
          "--hanko-to-x": `${-(frames - 1) * 100}px`,
          "--hanko-duration": `${durationMs}ms`,
          "--hanko-iteration": loop ? "infinite" : "1",
          "--hanko-fill": loop ? "none" : "forwards",
          // steps(1, jump-none) is invalid CSS, so a single-frame clip simply
          // doesn't animate — it's one static frame either way.
          "--hanko-anim-name": frames > 1 ? "hanko-sprite-play" : "none",
        } as React.CSSProperties
      }
    />
  );
}
