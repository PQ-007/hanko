import type { SpriteState } from "../_lib/sprites";
import { projectileFor } from "../_lib/projectiles";

// One shot in flight. Mounted for the length of its flight and then dropped by
// the parent — there is no exit state to manage, and remounting is what
// restarts the CSS animation for the next shot (the parent re-keys it, same
// trick FighterSprite uses for repeated identical poses).
//
// Endpoints are percentages of the arena row rather than measured pixels. At
// lg and up the two fighter slots flank the card symmetrically, so the
// fighters' centres land at a fixed fraction of the row whatever the
// breakpoint — 333 + 490 + 333 at xl puts them at 14% and 86%, and the same
// arithmetic holds at lg and 2xl to within a couple of percent.
const FROM = "14%";
const TO = "86%";

export default function ProjectileShot({
  slug,
  state,
  toward,
  durationMs,
}: {
  slug: string;
  state: SpriteState;
  /** Which way it travels. The player fires right, the monster fires left. */
  toward: "right" | "left";
  durationMs: number;
}) {
  const meta = projectileFor(slug, state);
  if (!meta) return null;

  const single = meta.frames < 2;
  return (
    <div
      // hidden below lg: see the note in globals.css — the wrapped layout has
      // no gap for a projectile to cross.
      className="hanko-projectile hidden lg:block"
      style={
        {
          backgroundImage: `url(/battle/projectiles/${slug}/${state}.png)`,
          "--hanko-shot-from": toward === "right" ? FROM : TO,
          "--hanko-shot-to": toward === "right" ? TO : FROM,
          "--hanko-shot-duration": `${durationMs}ms`,
          // The art points right; a monster's shot is the same sheet mirrored.
          "--hanko-shot-flip": toward === "left" ? "scaleX(-1)" : "",
          "--hanko-frame-w": `${meta.frames * 100}px`,
          "--hanko-to-x": `${-(meta.frames - 1) * 100}px`,
          // Loops several times over a ~260ms flight, so a bolt visibly
          // churns on its way across instead of stepping once and freezing.
          "--hanko-shot-frame-duration": `${meta.frames * 45}ms`,
          // steps(1, jump-none) is invalid CSS and would drop the whole
          // timing-function list, taking the flight with it. Single-frame
          // ammunition parks a valid 2 here and turns the animation off.
          "--hanko-frames": single ? 2 : meta.frames,
          "--hanko-shot-anim": single ? "none" : "hanko-sprite-play",
        } as React.CSSProperties
      }
    />
  );
}
