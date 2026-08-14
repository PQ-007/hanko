"use client";

import { useMemo, useState } from "react";
import type { Word } from "@/lib/types";
import { ACCENT } from "../_lib/chartColors";
import { addDays, formatDateMn, localDateKey, startOfDay } from "../_lib/dates";
import { T } from "../_lib/strings";
import { useInView, usePrefersReducedMotion } from "../_lib/useAnim";

const W = 640;
const H = 150;
const PAD_X = 8;
const PAD_TOP = 12;
const PAD_BOTTOM = 20;

// Cumulative vocabulary size over the trailing `days` days — the "line goes
// up" view of the collection. Single series, so no legend: the title names
// it, and the current total is direct-labeled at the right end.
export default function GrowthChart({ words, days = 90 }: { words: Word[]; days?: number }) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const reduced = usePrefersReducedMotion();
  const [hover, setHover] = useState<{ i: number } | null>(null);

  const points = useMemo(() => {
    const today = startOfDay(new Date());
    const start = addDays(today, -(days - 1));

    // Words added per day, then a running total seeded with everything that
    // already existed before the window opened.
    const perDay = new Map<string, number>();
    let before = 0;
    for (const w of words) {
      const added = startOfDay(new Date(w.date_added));
      if (added < start) {
        before += 1;
        continue;
      }
      const k = localDateKey(added);
      perDay.set(k, (perDay.get(k) ?? 0) + 1);
    }

    const series: { day: Date; total: number }[] = [];
    let running = before;
    for (let i = 0; i < days; i++) {
      const day = addDays(start, i);
      running += perDay.get(localDateKey(day)) ?? 0;
      series.push({ day, total: running });
    }
    return series;
  }, [words, days]);

  const maxTotal = Math.max(1, ...points.map((p) => p.total));
  const minTotal = Math.min(...points.map((p) => p.total));
  const span = Math.max(1, maxTotal - minTotal);

  const x = (i: number) => PAD_X + (i / Math.max(1, points.length - 1)) * (W - PAD_X * 2);
  const y = (v: number) =>
    PAD_TOP + (1 - (v - minTotal) / span) * (H - PAD_TOP - PAD_BOTTOM);

  const linePath = points.map((p, i) => `${i === 0 ? "M" : "L"}${x(i)},${y(p.total)}`).join(" ");
  const areaPath = `${linePath} L${x(points.length - 1)},${H - PAD_BOTTOM} L${x(0)},${H - PAD_BOTTOM} Z`;

  const active = hover ? points[hover.i] : points[points.length - 1];

  return (
    <div ref={ref} className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-semibold text-gray-500">{T.growthTitle(days)}</h3>
        <p className="text-xs text-gray-500">
          {formatDateMn(active.day)} — <span className="font-semibold text-gray-800">{active.total}</span> {T.wordsUnit}
        </p>
      </div>

      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="w-full"
        style={{ height: H }}
        preserveAspectRatio="none"
        onMouseLeave={() => setHover(null)}
        onMouseMove={(e) => {
          const r = e.currentTarget.getBoundingClientRect();
          const rel = ((e.clientX - r.left) / r.width) * W;
          const i = Math.round(((rel - PAD_X) / (W - PAD_X * 2)) * (points.length - 1));
          setHover({ i: Math.min(points.length - 1, Math.max(0, i)) });
        }}
      >
        <defs>
          <linearGradient id="growthFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={ACCENT} stopOpacity="0.22" />
            <stop offset="100%" stopColor={ACCENT} stopOpacity="0" />
          </linearGradient>
        </defs>

        <path d={areaPath} fill="url(#growthFill)" />
        <path
          d={linePath}
          fill="none"
          stroke={ACCENT}
          strokeWidth="2"
          strokeLinejoin="round"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
          style={
            reduced
              ? undefined
              : {
                  strokeDasharray: 2000,
                  strokeDashoffset: inView ? 0 : 2000,
                  transition: "stroke-dashoffset 1400ms ease-out",
                }
          }
        />

        {hover && (
          <>
            <line
              x1={x(hover.i)}
              y1={PAD_TOP}
              x2={x(hover.i)}
              y2={H - PAD_BOTTOM}
              stroke="#9ca3af"
              strokeWidth="1"
              strokeDasharray="3 3"
              vectorEffect="non-scaling-stroke"
            />
            <circle
              cx={x(hover.i)}
              cy={y(points[hover.i].total)}
              r="4"
              fill={ACCENT}
              stroke="#fff"
              strokeWidth="2"
              vectorEffect="non-scaling-stroke"
            />
          </>
        )}
      </svg>
    </div>
  );
}
