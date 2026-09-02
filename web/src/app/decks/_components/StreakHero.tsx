"use client";

import { Flame, GraduationCap, Plus, Snowflake } from "lucide-react";
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
  onPractice,
  onAddWord,
}: {
  streak: number;
  bestStreak: number;
  addedToday: number;
  masteredPct: number;
  freezesAvailable?: number;
  /** Opens the mode chooser. This used to be a link straight to the classic
      screen, which quietly made three of the four review modes unreachable
      from the dashboard. */
  onPractice: () => void;
  onAddWord: () => void;
}) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const shown = useCountUp(streak, 1000, inView);

  return (
    <div
      ref={ref}
      className="flex flex-col items-center justify-between gap-6 rounded-control border border-line-soft bg-white p-6 shadow-sm sm:flex-row sm:gap-8"
    >
      <div className="flex items-center gap-5">
        <div className="rounded-full bg-seal p-4 text-white">
          <Flame size={30} />
        </div>
        <div>
          <p className="text-[64px] font-semibold leading-none tracking-tight text-ink">
            {Math.round(shown)}
          </p>
          <p className="mt-1 text-sm font-medium text-ink">{T.streakLabel}</p>
          <p className="text-xs text-ink-mute">{T.bestStreak(bestStreak)}</p>
          {freezesAvailable > 0 && (
            <p className="mt-1 flex items-center gap-1 text-xs text-sky-600">
              <Snowflake size={12} /> {T.streakFreezes(freezesAvailable)}
            </p>
          )}
        </div>
      </div>

      <ProgressRing pct={masteredPct} label={T.masteredRingLabel} />

      <div className="flex flex-col items-center gap-2 sm:items-end">
        <p className="text-center text-sm text-ink-soft sm:text-right">
          {addedToday > 0 ? T.addedTodayCta(addedToday) : T.addedTodayNone}
        </p>
        {/* The line above is about words added today, so the way to add one
            belongs next to it — the dashboard otherwise reports on the
            collection without offering any way to change it. */}
        <div className="flex items-center gap-2">
          <button
            onClick={onAddWord}
            className="flex items-center gap-1.5 hk-btn hk-btn-quiet px-4 py-2.5 text-sm"
          >
            <Plus size={16} /> {T.quickAdd}
          </button>
          <button
            onClick={onPractice}
            className="flex items-center gap-1.5 hk-btn hk-btn-primary px-5 py-2.5 text-sm"
          >
            <GraduationCap size={16} /> {T.practiceAll}
          </button>
        </div>
      </div>
    </div>
  );
}
