"use client";

import { useState } from "react";
import type { Word } from "@/lib/types";
import { gradeFor } from "@/lib/srs";
import { GRADE_COLOR, GRADE_ORDER } from "../_lib/gradeColors";
import { T } from "../_lib/strings";
import { useInView, usePrefersReducedMotion } from "../_lib/useAnim";

// Column chart of how many words sit at each mastery grade. Ordinal data
// (order carries meaning) so it's one hue, light->dark = weak->strong, with
// "new" (never reviewed) as a neutral gray outside the ramp. Every bar is
// directly labeled with its count and grade letter, so color is
// reinforcement, never the only channel.
export default function GradeChart({ words, title }: { words: Word[]; title?: string }) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const reduced = usePrefersReducedMotion();
  const [hover, setHover] = useState<string | null>(null);

  const counts = new Map<string, number>(GRADE_ORDER.map((g) => [g, 0]));
  for (const w of words) {
    const g = gradeFor(w);
    counts.set(g, (counts.get(g) ?? 0) + 1);
  }
  const max = Math.max(1, ...GRADE_ORDER.map((g) => counts.get(g) ?? 0));
  const total = words.length;

  return (
    <div ref={ref} className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold text-gray-500">{title ?? T.gradeTitle}</h3>
      <div className="flex items-end gap-3">
        {GRADE_ORDER.map((g, i) => {
          const count = counts.get(g) ?? 0;
          const heightPct = count === 0 ? 0 : Math.max(6, (count / max) * 100);
          const pct = total === 0 ? 0 : Math.round((count / total) * 100);
          return (
            <div
              key={g}
              className="relative h-24 flex-1"
              onMouseEnter={() => setHover(g)}
              onMouseLeave={() => setHover(null)}
              title={`${g === "new" ? T.gradeNew : g} — ${count} (${pct}%)`}
            >
              <span
                style={{
                  bottom: `calc(${inView || reduced ? heightPct : 0}% + 4px)`,
                  transition: reduced ? undefined : `bottom 700ms cubic-bezier(.22,1,.36,1) ${i * 70}ms`,
                }}
                className="absolute left-1/2 -translate-x-1/2 text-xs font-medium text-gray-500"
              >
                {count}
              </span>
              <div
                style={{
                  height: `${inView || reduced ? heightPct : 0}%`,
                  backgroundColor: count === 0 ? "transparent" : GRADE_COLOR[g].fill,
                  transition: reduced
                    ? undefined
                    : `height 700ms cubic-bezier(.22,1,.36,1) ${i * 70}ms`,
                  opacity: hover === null || hover === g ? 1 : 0.45,
                }}
                className="absolute bottom-0 left-1/2 w-6 -translate-x-1/2 rounded-t-[4px]"
              />
              {hover === g && count > 0 && (
                <div className="pointer-events-none absolute -top-1 left-1/2 z-10 -translate-x-1/2 -translate-y-full whitespace-nowrap rounded bg-gray-900 px-2 py-1 text-[11px] font-medium text-white shadow-lg">
                  {count} ({pct}%)
                </div>
              )}
            </div>
          );
        })}
      </div>
      <div className="h-px bg-gray-200" />
      <div className="mt-1.5 flex gap-3">
        {GRADE_ORDER.map((g) => (
          <span key={g} className="flex-1 text-center text-xs text-gray-400">
            {g === "new" ? T.gradeNew : g}
          </span>
        ))}
      </div>
    </div>
  );
}
