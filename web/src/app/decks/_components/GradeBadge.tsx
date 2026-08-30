import type { Word } from "@/lib/types";
import { gradeFor } from "@/lib/srs";

// Large watermark letter showing the word's mastery grade (F/D/C/B/A), or
// "N" for never-reviewed (new) words. Rendered inside each card face (not
// the flip container) so it rotates along with the card. Decorative layer:
// content painted after it (with `relative`) sits on top.
export default function GradeBadge({ word }: { word: Word }) {
  const grade = gradeFor(word);
  const label = grade === "new" ? "N" : grade;

  return (
    <span
      aria-hidden
      className="pointer-events-none absolute -right-2 top-1/2 -translate-y-1/2 select-none text-[110px] font-semibold leading-none tracking-tighter text-paper-deep/70"
    >
      {label}
    </span>
  );
}
