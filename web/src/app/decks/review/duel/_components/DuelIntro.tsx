"use client";

import { useEffect, useState } from "react";
import { T } from "../../../_lib/strings";
import type { HeadToHead } from "../../../_lib/social";
import FighterSprite from "../../battle/_components/FighterSprite";
import H2HRecord from "./H2HRecord";

// The screen before a PvP match: who is across from you, and how the two of
// you have fared so far. It holds for INTRO_MS, counting down, then the arena
// takes over — long enough to read a record, short enough not to be a wait.

export const INTRO_MS = 4500;

export default function DuelIntro({
  heroSlug,
  youName,
  foeSlug,
  foeName,
  foeSub,
  record,
}: {
  heroSlug: string;
  youName: string;
  foeSlug: string;
  foeName: string;
  /** "@handle · level" under the name, when there is something to say. */
  foeSub?: string | null;
  /** Null while it is still loading. */
  record: HeadToHead | null;
}) {
  const [left, setLeft] = useState(Math.ceil(INTRO_MS / 1000));
  useEffect(() => {
    const started = Date.now();
    const id = setInterval(() => setLeft(Math.max(0, Math.ceil((INTRO_MS - (Date.now() - started)) / 1000))), 250);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="mx-auto flex min-h-full max-w-2xl flex-col justify-center px-2 py-4 pt-[max(1rem,env(safe-area-inset-top))] sm:px-4">
      <div className="hk-arena flex flex-col gap-5 p-5 sm:p-8">
        <p className="text-center text-[11px] font-semibold uppercase tracking-[0.16em] text-paper/40">
          {T.duelIntroKicker}
        </p>

        {/* A grid, so the two fighters, the VS and the two names each share a
            row — the opponent's extra "@handle · ELO" line can't push their
            name out of line with yours. */}
        <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-x-2 gap-y-1 sm:gap-x-6">
          <div className="hanko-fighter-slot flex shrink-0 items-center justify-center justify-self-center">
            <FighterSprite slug={heroSlug} state="idle" preload={["idle"]} />
          </div>
          <span className="text-2xl font-black tracking-wider text-paper/30">VS</span>
          <div className="hanko-fighter-slot flex shrink-0 items-center justify-center justify-self-center">
            <FighterSprite slug={foeSlug} state="idle" flip preload={["idle"]} />
          </div>

          <span className="min-w-0 self-start truncate text-center text-sm font-bold text-paper">{youName}</span>
          <span />
          <span className="flex min-w-0 flex-col items-center self-start text-center">
            <span className="max-w-full truncate text-sm font-bold text-paper">{foeName}</span>
            {foeSub && <span className="max-w-full truncate text-[11px] text-paper/45">{foeSub}</span>}
          </span>
        </div>

        {record ? (
          <H2HRecord record={record} youName={youName} themName={foeName} />
        ) : (
          <div className="h-28 animate-pulse rounded-card bg-white/5" />
        )}

        <p className="text-center text-sm font-semibold tabular-nums text-paper/70">
          {left > 0 ? T.duelIntroStarting(left) : T.duelIntroGo}
        </p>
      </div>
    </div>
  );
}
