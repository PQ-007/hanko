"use client";

import { useMemo, useState } from "react";
import { ACCENT } from "../_lib/chartColors";
import { addDays, localDateKey, startOfDay, WEEKDAY_MN } from "../_lib/dates";
import { T } from "../_lib/strings";
import { useInView, usePrefersReducedMotion } from "../_lib/useAnim";

// Reviews already done, bucketed by day of the week — the "when do I actually
// study?" view. Single series, so no legend: the title names it and every bar
// is directly labeled. Uses the same trailing window as the heatmap so the
// two charts always describe the same stretch of time.
export default function WeekdayReviewsChart({
  counts,
  weeks = 26,
}: {
  counts: Map<string, number>;
  weeks?: number;
}) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const reduced = usePrefersReducedMotion();
  const [hover, setHover] = useState<number | null>(null);

  const { totals, activeWeeks, grand } = useMemo(() => {
    const today = startOfDay(new Date());
    const totals = new Array(7).fill(0) as number[];
    // Days on which that weekday actually occurred in the window, so the
    // average below divides by real opportunities rather than a flat 26.
    const seen = new Array(7).fill(0) as number[];

    for (let i = 0; i < weeks * 7; i++) {
      const day = addDays(today, -i);
      const w = day.getDay();
      seen[w] += 1;
      totals[w] += counts.get(localDateKey(day)) ?? 0;
    }
    return {
      totals,
      activeWeeks: seen,
      grand: totals.reduce((a, b) => a + b, 0),
    };
  }, [counts, weeks]);

  const max = Math.max(1, ...totals);
  const todayIdx = new Date().getDay();

  return (
    <div ref={ref} className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
      <div className="mb-4 flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-semibold text-gray-500">{T.weekdayTitle}</h3>
        <p className="text-xs text-gray-400">{T.weekdaySummary(grand)}</p>
      </div>

      <div className="flex items-end gap-3">
        {totals.map((count, i) => {
          const heightPct = count === 0 ? 0 : Math.max(6, (count / max) * 100);
          const avg = activeWeeks[i] === 0 ? 0 : count / activeWeeks[i];
          return (
            <div
              key={i}
              className="relative h-24 flex-1"
              onMouseEnter={() => setHover(i)}
              onMouseLeave={() => setHover(null)}
              title={`${WEEKDAY_MN[i]} — ${T.reviewsN(count)}`}
            >
              <span
                style={{
                  bottom: `calc(${inView || reduced ? heightPct : 0}% + 4px)`,
                  transition: reduced
                    ? undefined
                    : `bottom 700ms cubic-bezier(.22,1,.36,1) ${i * 70}ms`,
                }}
                className="absolute left-1/2 -translate-x-1/2 text-xs font-medium text-gray-500"
              >
                {count}
              </span>
              <div
                style={{
                  height: `${inView || reduced ? heightPct : 0}%`,
                  backgroundColor: count === 0 ? "transparent" : ACCENT,
                  transition: reduced
                    ? undefined
                    : `height 700ms cubic-bezier(.22,1,.36,1) ${i * 70}ms`,
                  opacity: hover === null || hover === i ? 1 : 0.45,
                }}
                className="absolute bottom-0 left-1/2 w-6 -translate-x-1/2 rounded-t-[4px]"
              />
              {hover === i && (
                <div className="pointer-events-none absolute -top-1 left-1/2 z-10 -translate-x-1/2 -translate-y-full whitespace-nowrap rounded bg-gray-900 px-2 py-1 text-[11px] font-medium text-white shadow-lg">
                  {T.reviewsN(count)} · {T.perWeekAvg(Math.round(avg * 10) / 10)}
                </div>
              )}
            </div>
          );
        })}
      </div>
      <div className="h-px bg-gray-200" />
      <div className="mt-1.5 flex gap-3">
        {WEEKDAY_MN.map((w, i) => (
          <span
            key={w}
            // Today is marked with weight, not color — the bars own the hue.
            className={`flex-1 text-center text-xs ${
              i === todayIdx ? "font-semibold text-gray-700" : "text-gray-400"
            }`}
          >
            {w}
          </span>
        ))}
      </div>
    </div>
  );
}
