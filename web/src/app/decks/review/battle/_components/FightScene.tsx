"use client";

import { useEffect, useRef, useState } from "react";
import { pickMonster, PLAYER_ROSTER } from "../_lib/monsters";
import { critPose, ONE_SHOT_MS, type SpriteState } from "../_lib/sprites";
import FighterSprite from "./FighterSprite";

// A looping fight: two characters walk on, trade blows, one goes down, and a
// new pair walks on. Used as the app's loading state and as the Monster Hunt
// card's artwork on the practice landing page.
//
// There is deliberately no idle in the loop. An idle pose is what a character
// does when nothing is happening, which is the opposite of what either of
// these two places is for — one is covering a wait, the other is selling a
// fight. Every phase here is movement or a blow.
//
// Everything is decoration and must stay that way: it owns no data, and
// whatever mounts it decides when it goes away.

const WALK_MS = 1300;
const CLASH_MS = ONE_SHOT_MS + 40; // one attack clip, plus a beat to land
const FINISH_MS = 1100; // the death clip, held long enough to register
const EXCHANGES = 4; // blows traded before somebody drops

// Only the clips this scene can reach. Narrowing the preload matters: a new
// pair every few seconds, warming every sheet each time, would have a loading
// animation fighting the request it exists to cover.
const SCENE_CLIPS: SpriteState[] = [
  "walk",
  "attack01",
  "attack02",
  "attack03",
  "hurt",
  "death",
];

type Phase =
  | { kind: "approach" }
  // `pose` is resolved per blow so the fight isn't four identical swings.
  | { kind: "clash"; attacker: "hero" | "monster"; pose: SpriteState }
  | { kind: "finish"; loser: "hero" | "monster"; pose: SpriteState };

function randomHero() {
  return PLAYER_ROSTER[Math.floor(Math.random() * PLAYER_ROSTER.length)];
}

export default function FightScene({
  hero,
  slotClass,
  gapClass = "gap-1 sm:gap-3",
  label,
  heroWins = false,
}: {
  /** Fixed fighter, or undefined to draw a new one with each pair. */
  hero?: string;
  /** Which sizing class the two slots use — see globals.css. */
  slotClass: string;
  gapClass?: string;
  label?: string;
  /**
   * When the hero is the viewer's own chosen character, they should not be
   * watching themselves lose on a card whose job is to start the fight.
   */
  heroWins?: boolean;
}) {
  // Cast is drawn after mount, never in a render body: this can be
  // server-rendered, and Math.random() during render gives the server and the
  // client different fighters — a hydration mismatch. Until it resolves the
  // scene isn't drawn.
  const [cast, setCast] = useState<{ hero: string; monster: string } | null>(null);
  const [phase, setPhase] = useState<Phase>({ kind: "approach" });
  const [round, setRound] = useState(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Read by the loop without restarting it: a fixed hero can change under us
  // (the picker sits right beside this on the landing page) and the fight
  // should pick the new character up on its next pair, not tear down mid-blow.
  const heroRef = useRef(hero);
  useEffect(() => {
    heroRef.current = hero;
  }, [hero]);

  useEffect(() => {
    let cancelled = false;
    let blow = 0;

    // Three characters are on both rosters now, so the monster is drawn with
    // the hero excluded — two identical sprites squaring up looks like a bug,
    // not a mirror match.
    function newPair() {
      const h = heroRef.current ?? randomHero();
      return { hero: h, monster: pickMonster(h) };
    }

    let pair = newPair();

    function advance() {
      if (cancelled) return;
      blow += 1;

      if (blow <= EXCHANGES) {
        const attacker = blow % 2 === 1 ? "hero" : "monster";
        const slug = attacker === "hero" ? pair.hero : pair.monster;
        // Every third blow is the character's heaviest clip, so the exchange
        // escalates instead of repeating. critPose resolves against the real
        // metadata, so a character without a third attack still swings.
        const pose: SpriteState = blow % 3 === 0 ? critPose(slug) : "attack01";
        setPhase({ kind: "clash", attacker, pose });
        timer.current = setTimeout(advance, CLASH_MS);
        return;
      }

      if (blow === EXCHANGES + 1) {
        // Somebody has to lose. Where the hero is anonymous, it isn't always
        // the monster — a scene where the hero always wins stops being
        // interesting on the third viewing.
        const loser: "hero" | "monster" =
          heroWins || Math.random() < 0.5 ? "monster" : "hero";
        const winner = loser === "hero" ? pair.monster : pair.hero;
        setPhase({ kind: "finish", loser, pose: critPose(winner) });
        timer.current = setTimeout(advance, FINISH_MS);
        return;
      }

      pair = newPair();
      setCast(pair);
      setPhase({ kind: "approach" });
      setRound((n) => n + 1);
      blow = 0;
      timer.current = setTimeout(advance, WALK_MS);
    }

    setCast(pair);
    timer.current = setTimeout(advance, WALK_MS);
    return () => {
      cancelled = true;
      if (timer.current) clearTimeout(timer.current);
    };
  }, [heroWins]);

  // One resolver for both fighters: whoever is swinging shows the attack, the
  // other one takes it. A function rather than two ternaries in the JSX,
  // because the finishing blow makes the pairing asymmetric.
  function poseOf(who: "hero" | "monster"): SpriteState {
    if (phase.kind === "approach") return "walk";
    if (phase.kind === "finish") return phase.loser === who ? "death" : phase.pose;
    return phase.attacker === who ? phase.pose : "hurt";
  }

  // The chosen character wins immediately, without waiting for the next pair:
  // the sprite prop is read live, so only the pose machine is on a timer.
  const heroSlug = hero ?? cast?.hero;

  return (
    <div className="flex flex-col items-center gap-4">
      <div
        // Re-keyed per pair so the walk-on animation replays for each new one
        // instead of only ever running once, on mount.
        key={round}
        className={`flex items-end justify-center ${gapClass}`}
        style={{ ["--hanko-walk-ms" as string]: `${WALK_MS}ms` }}
      >
        {cast && heroSlug && (
          <>
            <div className={`${slotClass} hanko-walk-on-left flex items-center justify-center`}>
              <FighterSprite slug={heroSlug} preload={SCENE_CLIPS} state={poseOf("hero")} />
            </div>
            <div className={`${slotClass} hanko-walk-on-right flex items-center justify-center`}>
              <FighterSprite
                slug={cast.monster}
                preload={SCENE_CLIPS}
                state={poseOf("monster")}
                flip
              />
            </div>
          </>
        )}
      </div>
      {label && <p className="text-sm text-ink-soft">{label}</p>}
    </div>
  );
}
