"use client";

import Link from "next/link";
import { Flame, GraduationCap, Snowflake } from "lucide-react";
import { T } from "../_lib/strings";
import { useCountUp, useInView } from "../_lib/useAnim";
import ProgressRing from "./ProgressRing";

// The one hero figure on the dashboard: the current streak, the number that
// most rewards showing up again tomorrow. Exactly one per view by design —
// everything else on the page stays at stat-tile scale.
export default function StreakHero({
  streak,
  bestStreak,
  addedToday,
  masteredPct,
  freezesAvailable = 0,
}: {
  streak: number;
  bestStreak: number;
  addedToday: number;
  masteredPct: number;
  freezesAvailable?: number;
}) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const shown = useCountUp(streak, 1000, inView);

  return (
    <div
      ref={ref}
      className="flex flex-col items-center justify-between gap-6 rounded-lg border border-gray-200 bg-white p-6 shadow-sm sm:flex-row sm:gap-8"
    >
      <div className="flex items-center gap-5">
        <div className="rounded-full bg-gray-900 p-4 text-white">
          <Flame size={30} />
        </div>
        <div>
          <p className="text-[64px] font-semibold leading-none tracking-tight text-gray-900">
            {Math.round(shown)}
          </p>
          <p className="mt-1 text-sm font-medium text-gray-700">{T.streakLabel}</p>
          <p className="text-xs text-gray-400">{T.bestStreak(bestStreak)}</p>
          {freezesAvailable > 0 && (
            <p className="mt-1 flex items-center gap-1 text-xs text-sky-600">
              <Snowflake size={12} /> {T.streakFreezes(freezesAvailable)}
            </p>
          )}
        </div>
      </div>

      <ProgressRing pct={masteredPct} label={T.masteredRingLabel} />

      <div className="flex flex-col items-center gap-2 sm:items-end">
        <p className="text-center text-sm text-gray-600 sm:text-right">
          {addedToday > 0 ? T.addedTodayCta(addedToday) : T.addedTodayNone}
        </p>
        <Link
          href="/decks/practice"
          className="flex items-center gap-1.5 rounded-lg bg-gray-900 px-5 py-2.5 text-sm font-medium text-white shadow-sm transition hover:bg-gray-800"
        >
          <GraduationCap size={16} /> {T.practiceAll}
        </Link>
      </div>
    </div>
  );
}
