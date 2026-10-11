"use client";

import { useEffect, useState } from "react";
import FighterSprite from "../../battle/_components/FighterSprite";
import { SPRITES, type SpriteState } from "../../battle/_lib/sprites";
import { emotePose } from "../_lib/chat";
import type { Beat } from "../_lib/useDuelChat";

// How long an emote's pose holds before the fighter settles back, and how long
// a speech bubble stays up.
const POSE_MS = 1200;
const BUBBLE_MS = 3200;

/**
 * A fighter that can be talked through: plays an emote's pose on its own
 * sprite, then settles back to `base`, and shows the latest message in a
 * speech bubble above it. Used by the ready room and the result screen.
 */
export default function ChatFighter({
  slug,
  base,
  flip = false,
  beat,
  slotClass = "hanko-fighter-slot",
}: {
  slug: string;
  base: SpriteState;
  flip?: boolean;
  beat: Beat | null;
  slotClass?: string;
}) {
  const [pose, setPose] = useState<SpriteState | null>(null);
  const [bubble, setBubble] = useState<Beat | null>(null);

  useEffect(() => {
    if (!beat) return;
    const available = Object.keys(SPRITES[slug] ?? {});
    // eslint-disable-next-line react-hooks/set-state-in-effect -- each new beat restarts the animation
    setBubble(beat);
    setPose(beat.emote ? emotePose(available, beat.emote) : null);
    const settle = setTimeout(() => setPose(null), POSE_MS);
    const hide = setTimeout(() => setBubble(null), BUBBLE_MS);
    return () => {
      clearTimeout(settle);
      clearTimeout(hide);
    };
  }, [beat, slug]);

  return (
    <div className={`${slotClass} relative flex shrink-0 items-center justify-center justify-self-center`}>
      {/* Keyed by the beat, so the same emote twice replays from frame one. */}
      <FighterSprite key={pose ? `${pose}-${bubble?.nonce}` : base} slug={slug} state={pose ?? base} flip={flip} />
      {bubble && (
        <span
          key={bubble.nonce}
          className={`hk-chip-new pointer-events-none absolute left-1/2 top-0 z-10 max-w-[11rem] -translate-x-1/2 -translate-y-1/2 break-words rounded-2xl bg-white px-3 py-1.5 text-center font-semibold leading-snug text-zinc-900 shadow-lg ${
            bubble.emote ? "text-2xl" : "text-xs"
          }`}
        >
          {bubble.text}
          <span className="absolute left-1/2 top-full h-0 w-0 -translate-x-1/2 border-x-[6px] border-t-[7px] border-x-transparent border-t-white" />
        </span>
      )}
    </div>
  );
}
