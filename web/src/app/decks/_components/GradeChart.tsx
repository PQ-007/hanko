"use client";

import type { Word } from "@/lib/types";
import { gradeFor } from "@/lib/srs";
import { GRADE_COLOR, GRADE_ORDER } from "../_lib/gradeColors";
import { T } from "../_lib/strings";

// Column chart of how many words in a deck sit at each mastery grade. Ordinal
// data (order carries meaning) so it's one hue, light->dark = weak->strong,
// with "new" (never reviewed) as a neutral gray outside the ramp. Every bar is
// directly labeled with its count and grade letter, so color is reinforcement,
// never the only channel.
export default function GradeChart({ words, title }: { words: Word[]; title?: string }) {
  const counts = new Map<string, number>(GRADE_ORDER.map((g) => [g, 0]));
  for (const w of words) {
    const g = gradeFor(w);
    counts.set(g, (counts.get(g) ?? 0) + 1);
  }
  const max = Math.max(1, ...GRADE_ORDER.map((g) => counts.get(g) ?? 0));

  return (
    <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
      <h3 className="mb-4 text-sm font-semibold text-gray-500">{title ?? T.gradeTitle}</h3>
      <div className="flex items-end gap-3">
        {GRADE_ORDER.map((g) => {
          const count = counts.get(g) ?? 0;
          const heightPct = count === 0 ? 0 : Math.max(6, (count / max) * 100);
          return (
            <div key={g} className="relative h-20 flex-1">
              <span
                style={{ bottom: `calc(${heightPct}% + 4px)` }}
                className="absolute left-1/2 -translate-x-1/2 text-xs font-medium text-gray-500"
              >
                {count}
              </span>
              <div
                style={{
                  height: `${heightPct}%`,
                  backgroundColor: count === 0 ? "transparent" : GRADE_COLOR[g].fill,
                }}
                className="absolute bottom-0 left-1/2 w-6 -translate-x-1/2 rounded-t-[4px]"
              />
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
