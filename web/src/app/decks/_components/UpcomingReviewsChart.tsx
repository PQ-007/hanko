"use client";

import type { Word } from "@/lib/types";
import { T } from "../_lib/strings";

const WEEKDAY_MN = ["Ня", "Да", "Мя", "Лх", "Пү", "Ба", "Бя"];
const ACCENT = "#3987e5"; // same blue step GradeChart uses for grade "D"

function startOfDay(d: Date) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

// Single-series forecast of how many words come due over the next 7 days
// (today's bucket also absorbs anything already overdue, matching the
// practice queue's `due_at <= now` semantics). One hue, direct count labels —
// same bar shape as GradeChart, no legend needed for a single series.
export default function UpcomingReviewsChart({ words }: { words: Word[] }) {
  const today = startOfDay(new Date());
  const buckets = Array.from({ length: 7 }, (_, i) => {
    const day = new Date(today);
    day.setDate(day.getDate() + i);
    const next = new Date(day);
    next.setDate(next.getDate() + 1);
    return { day, next, count: 0 };
  });

  for (const w of words) {
    const due = new Date(w.due_at);
    if (due < buckets[0].next) {
      buckets[0].count += 1;
      continue;
    }
    const bucket = buckets.find((b) => due >= b.day && due < b.next);
    if (bucket) bucket.count += 1;
  }

  const max = Math.max(1, ...buckets.map((b) => b.count));

  return (
    <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold text-gray-500">{T.upcomingTitle}</h3>
      <div className="flex items-end gap-3">
        {buckets.map((b, i) => {
          const heightPct = b.count === 0 ? 0 : Math.max(6, (b.count / max) * 100);
          return (
            <div key={i} className="relative h-20 flex-1">
              <span
                style={{ bottom: `calc(${heightPct}% + 4px)` }}
                className="absolute left-1/2 -translate-x-1/2 text-xs font-medium text-gray-500"
              >
                {b.count}
              </span>
              <div
                style={{
                  height: `${heightPct}%`,
                  backgroundColor: b.count === 0 ? "transparent" : ACCENT,
                }}
                className="absolute bottom-0 left-1/2 w-6 -translate-x-1/2 rounded-t-[4px]"
              />
            </div>
          );
        })}
      </div>
      <div className="h-px bg-gray-200" />
      <div className="mt-1.5 flex gap-3">
        {buckets.map((b, i) => (
          <span key={i} className="flex-1 text-center text-xs text-gray-400">
            {i === 0 ? T.todayLabel : WEEKDAY_MN[b.day.getDay()]}
          </span>
        ))}
      </div>
    </div>
  );
}
