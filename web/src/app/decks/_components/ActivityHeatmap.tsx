"use client";

import { useMemo, useRef, useState } from "react";
import { HEATMAP_EMPTY, HEATMAP_STEPS, heatmapColor } from "../_lib/chartColors";
import {
  addDays,
  formatDateMn,
  localDateKey,
  MONTH_MN,
  startOfDay,
  WEEKDAY_MN,
} from "../_lib/dates";
import { T } from "../_lib/strings";
import { useInView, usePrefersReducedMotion } from "../_lib/useAnim";

const CELL = 13; // px; the 3px flex gap supplies the surface gap between fills

export interface DayActivity {
  key: string;
  count: number;
}

// Calendar heatmap of daily review volume over the trailing `weeks` weeks.
// Magnitude data -> one validated blue hue, light->dark, with "no activity"
// as a neutral outside the ramp. Cells carry a hover tooltip and a title
// attribute, and the same numbers are available in the summary line below,
// so the color is never the only channel.
export default function ActivityHeatmap({
  counts,
  title,
  formatCount,
  weeks = 26,
}: {
  counts: Map<string, number>;
  title: string;
  // Renders a day's value with its unit ("12 давталт" / "12 үг"), used in
  // both the tooltip and the summary line.
  formatCount: (n: number) => string;
  weeks?: number;
}) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const reduced = usePrefersReducedMotion();
  // Tooltip coordinates are measured against this element, so the lookup
  // can't break if an intermediate wrapper ever gains a `relative` class.
  const plotRef = useRef<HTMLDivElement>(null);
  const [hover, setHover] = useState<{ day: Date; count: number; x: number; y: number } | null>(
    null
  );

  // Build columns of 7 days ending on today, aligned so each column starts on
  // Sunday (matching the weekday rail on the left).
  const { columns, max, total, activeDays } = useMemo(() => {
    const today = startOfDay(new Date());
    // Walk back to the Sunday that begins the earliest visible week.
    const end = addDays(today, 6 - today.getDay()); // Saturday of this week
    const start = addDays(end, -(weeks * 7 - 1));

    const cols: { day: Date; count: number; future: boolean }[][] = [];
    let max = 0;
    let total = 0;
    let activeDays = 0;

    for (let w = 0; w < weeks; w++) {
      const col: { day: Date; count: number; future: boolean }[] = [];
      for (let d = 0; d < 7; d++) {
        const day = addDays(start, w * 7 + d);
        const count = counts.get(localDateKey(day)) ?? 0;
        if (count > max) max = count;
        total += count;
        if (count > 0) activeDays += 1;
        col.push({ day, count, future: day > today });
      }
      cols.push(col);
    }
    return { columns: cols, max, total, activeDays };
  }, [counts, weeks]);

  // Month label sits above the first column whose month differs from the previous.
  const monthLabels = columns.map((col, i) => {
    const first = col[0].day;
    if (i === 0) return null; // avoid a clipped label at the left edge
    const prev = columns[i - 1][0].day;
    return first.getMonth() !== prev.getMonth() ? MONTH_MN[first.getMonth()] : null;
  });

  return (
    <div
      ref={ref}
      className="rounded-control border border-line-soft bg-white p-4 shadow-sm"
    >
      <div className="mb-1 flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-semibold text-ink-soft">{title}</h3>
        <p className="text-xs text-ink-mute">
          {T.heatmapSummary(formatCount(total), activeDays)}
        </p>
      </div>

      <div ref={plotRef} className="relative overflow-x-auto pb-1">
        {/* w-max keeps the grid at its natural size; mx-auto centers it when
            the card is wider than the calendar, instead of stranding a block
            of dead space on the right. */}
        <div className="mx-auto flex w-max gap-[3px]">
          {/* Weekday rail — label alternate rows to keep it uncluttered */}
          <div
            className="mr-1 flex shrink-0 flex-col gap-[3px] pt-[18px]"
            aria-hidden
          >
            {WEEKDAY_MN.map((w, i) => (
              <div
                key={w}
                style={{ height: CELL, lineHeight: `${CELL}px` }}
                className="text-[9px] text-ink-mute"
              >
                {i % 2 === 1 ? w : ""}
              </div>
            ))}
          </div>

          {columns.map((col, ci) => (
            <div key={ci} className="flex shrink-0 flex-col gap-[3px]">
              <div
                style={{ height: 15 }}
                className="whitespace-nowrap text-[9px] leading-[15px] text-ink-mute"
              >
                {monthLabels[ci] ?? ""}
              </div>
              {col.map(({ day, count, future }, di) => {
                if (future) {
                  return <div key={di} style={{ width: CELL, height: CELL }} />;
                }
                const delay = reduced ? 0 : ci * 12 + di * 4;
                return (
                  <div
                    key={di}
                    title={`${formatDateMn(day)} — ${formatCount(count)}`}
                    onMouseEnter={(e) => {
                      const host = plotRef.current;
                      if (!host) return;
                      const r = e.currentTarget.getBoundingClientRect();
                      const h = host.getBoundingClientRect();
                      setHover({
                        day,
                        count,
                        // Offset by scroll so the tooltip tracks the cell
                        // inside the horizontally scrollable plot.
                        x: r.left - h.left + host.scrollLeft + r.width / 2,
                        y: r.top - h.top,
                      });
                    }}
                    onMouseLeave={() => setHover(null)}
                    style={{
                      width: CELL,
                      height: CELL,
                      backgroundColor: heatmapColor(count, max),
                      opacity: inView || reduced ? 1 : 0,
                      transform: inView || reduced ? "scale(1)" : "scale(0.4)",
                      transition: reduced
                        ? undefined
                        : `opacity 260ms ease-out ${delay}ms, transform 260ms ease-out ${delay}ms`,
                    }}
                    className="rounded-[3px] ring-inset hover:ring-2 hover:ring-ink/40"
                  />
                );
              })}
            </div>
          ))}
        </div>

        {hover && (
          <div
            style={{ left: hover.x, top: hover.y - 8 }}
            className="pointer-events-none absolute z-10 -translate-x-1/2 -translate-y-full whitespace-nowrap rounded-control bg-ink px-2 py-1 text-[11px] font-medium text-paper shadow-lift"
          >
            {formatDateMn(hover.day)} — {formatCount(hover.count)}
          </div>
        )}
      </div>

      {/* Sequential scale legend */}
      <div className="mt-2 flex items-center justify-end gap-1.5 text-[10px] text-ink-mute">
        <span>{T.less}</span>
        <div style={{ width: 10, height: 10, backgroundColor: HEATMAP_EMPTY }} className="rounded-[2px]" />
        {HEATMAP_STEPS.map((c) => (
          <div
            key={c}
            style={{ width: 10, height: 10, backgroundColor: c }}
            className="rounded-[2px]"
          />
        ))}
        <span>{T.more}</span>
      </div>
    </div>
  );
}
