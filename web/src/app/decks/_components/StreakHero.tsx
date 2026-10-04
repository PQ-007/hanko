"use client";

import { Flame, GraduationCap, Pencil, Plus, Snowflake } from "lucide-react";
import { T } from "../_lib/strings";
import { useCountUp, useInView } from "../_lib/useAnim";
import { RING_ADDED, RING_GOAL } from "../_lib/chartColors";
import ProgressRing from "./ProgressRing";

// The one hero figure on the dashboard: the current streak, the number that
// most rewards showing up again tomorrow. Exactly one per view by design —
// everything else on the page stays at stat-tile scale.
export default function StreakHero({
  streak,
  bestStreak,
  addedToday,
  masteredPct,
  newGoal,
  newReviewedToday,
  freezesAvailable = 0,
  onPractice,
  onAddWord,
  onEditGoal,
}: {
  streak: number;
  bestStreak: number;
  addedToday: number;
  masteredPct: number;
  /** profiles.new_per_day — today's new-card goal. Not a new setting: this
      already exists as the daily-cap preference, just surfaced here too. */
  newGoal: number;
  /** New cards (state_before='new') answered today. A review/relearning
      answer does not move this number, only a first-time card does. */
  newReviewedToday: number;
  freezesAvailable?: number;
  /** Opens the mode chooser. This used to be a link straight to the classic
      screen, which quietly made three of the four review modes unreachable
      from the dashboard. */
  onPractice: () => void;
  onAddWord: () => void;
  /** Opens GoalModal to edit newGoal. */
  onEditGoal: () => void;
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

      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onEditGoal}
          title={T.goalRingEdit}
          aria-label={T.goalRingEdit}
          className="group relative rounded-full"
        >
          <ProgressRing
            pct={newGoal > 0 ? Math.min(100, Math.round((newReviewedToday / newGoal) * 100)) : newReviewedToday > 0 ? 100 : 0}
            centerText={`${newReviewedToday}/${newGoal}`}
            label={T.goalRingLabel}
            size={104}
            stroke={9}
            color={RING_GOAL}
          />
          <span className="pointer-events-none absolute right-0 top-0 flex h-6 w-6 items-center justify-center rounded-full bg-ink text-paper opacity-0 shadow-sm transition group-hover:opacity-100">
            <Pencil size={12} />
          </span>
        </button>
        <ProgressRing pct={masteredPct} label={T.masteredRingLabel} size={104} stroke={9} />
        <ProgressRing
          pct={100}
          centerText={String(addedToday)}
          label={T.addedRingLabel}
          size={104}
          stroke={9}
          color={RING_ADDED}
        />
      </div>

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
