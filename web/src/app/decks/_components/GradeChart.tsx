"use client";

import { useState } from "react";
import type { Word } from "@/lib/types";
import { gradeFor, type Grade } from "@/lib/srs";
import { GRADE_COLOR, GRADE_ORDER } from "../_lib/gradeColors";
import { T } from "../_lib/strings";
import { useInView, usePrefersReducedMotion } from "../_lib/useAnim";

// Column chart of how many words sit at each mastery grade. Ordinal data
// (order carries meaning) so it's one hue, light->dark = weak->strong, with
// "new" (never reviewed) as a neutral gray outside the ramp. Every bar is
// directly labeled with its count and grade letter, so color is
// reinforcement, never the only channel.
//
// Bars double as a filter: click one to narrow the word list below to that
// grade, click again (or the same bar) to clear it. Counts always reflect
// `words` as passed in (the full deck), never the filtered-down list, so the
// chart doesn't shrink out from under itself once a filter is active.
export default function GradeChart({
  words,
  title,
  selected = null,
  onSelect,
}: {
  words: Word[];
  title?: string;
  selected?: Grade | null;
  onSelect?: (grade: Grade | null) => void;
}) {
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
    <div ref={ref} className="rounded-control border border-line-soft bg-surface p-4 shadow-sm">
      <h3 className="mb-5 text-sm font-semibold text-ink-soft">{title ?? T.gradeTitle}</h3>
      <div className="flex items-end gap-3">
        {GRADE_ORDER.map((g, i) => {
          const count = counts.get(g) ?? 0;
          // Capped below 100: the count label sits just above the bar top, so
          // an uncapped bar at the max value pushed its label past the box's
          // own top edge and into the title row above it.
          const heightPct = count === 0 ? 0 : Math.min(80, Math.max(6, (count / max) * 100));
          const pct = total === 0 ? 0 : Math.round((count / total) * 100);
          const isSelected = selected === g;
          return (
            <button
              key={g}
              type="button"
              disabled={!onSelect || count === 0}
              onClick={() => onSelect?.(isSelected ? null : g)}
              className="relative h-28 flex-1 disabled:cursor-default"
              onMouseEnter={() => setHover(g)}
              onMouseLeave={() => setHover(null)}
              title={`${g === "new" ? T.gradeNew : g} — ${count} (${pct}%)`}
            >
              <span
                style={{
                  bottom: `calc(${inView || reduced ? heightPct : 0}% + 4px)`,
                  transition: reduced ? undefined : `bottom 700ms cubic-bezier(.22,1,.36,1) ${i * 70}ms`,
                }}
                className="absolute left-1/2 -translate-x-1/2 text-xs font-medium text-ink-soft"
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
                  opacity: hover === null || hover === g || isSelected ? 1 : 0.45,
                  outline: isSelected ? "2px solid var(--color-ink, #0b0b0b)" : undefined,
                  outlineOffset: isSelected ? "2px" : undefined,
                }}
                className="absolute bottom-0 left-1/2 w-6 -translate-x-1/2 rounded-t-[4px]"
              />
              {hover === g && count > 0 && (
                <div className="pointer-events-none absolute -top-1 left-1/2 z-10 -translate-x-1/2 -translate-y-full whitespace-nowrap rounded-control bg-ink px-2 py-1 text-[11px] font-medium text-paper shadow-lift">
                  {count} ({pct}%)
                </div>
              )}
            </button>
          );
        })}
      </div>
      <div className="h-px bg-paper-deep" />
      <div className="mt-1.5 flex gap-3">
        {GRADE_ORDER.map((g) => (
          <span
            key={g}
            className={`flex-1 text-center text-xs ${selected === g ? "font-semibold text-ink" : "text-ink-mute"}`}
          >
            {g === "new" ? T.gradeNew : g}
          </span>
        ))}
      </div>
      {selected !== null && onSelect && (
        <button
          type="button"
          onClick={() => onSelect(null)}
          className="mt-2 text-xs font-medium text-ink-soft underline-offset-2 hover:underline"
        >
          {T.gradeClearFilter}
        </button>
      )}
    </div>
  );
}
