"use client";

import type { Rating } from "@/lib/srs";
import { T } from "../../_lib/strings";

// Each button states the label and its number key. Deliberately no interval
// preview ("6 өдөр") on the button itself — showing the scheduled gap read as
// a forgetting-date prediction rather than "when I'll ask again," and was
// confusing enough in practice that it's worth not showing at all.
const OPTIONS: {
  rating: Rating;
  key: string;
  label: string;
  className: string;
}[] = [
  {
    rating: "again",
    key: "1",
    label: T.again,
    className: "border-red-200 bg-red-50/60 text-red-700 hover:bg-red-100",
  },
  {
    rating: "hard",
    key: "2",
    label: T.hard,
    className: "border-amber-200 bg-amber-50/60 text-amber-800 hover:bg-amber-100",
  },
  {
    rating: "good",
    key: "3",
    label: T.good,
    className: "border-seal bg-seal text-paper hover:bg-seal-dark",
  },
  {
    rating: "easy",
    key: "4",
    label: T.easy,
    className: "border-emerald-200 bg-emerald-50/60 text-emerald-800 hover:bg-emerald-100",
  },
];

export default function RatingButtons({
  onRate,
}: {
  onRate: (rating: Rating) => void;
}) {
  return (
    <div className="grid w-full grid-cols-2 gap-2 sm:grid-cols-4">
      {OPTIONS.map(({ rating, key, label, className }) => (
        <button
          key={rating}
          onClick={() => onRate(rating)}
          className={`flex flex-col items-center gap-0.5 rounded-control border px-3 py-2.5 transition ${className}`}
        >
          <span className="flex items-center gap-1.5 text-sm font-semibold">
            {label}
            <kbd className="rounded-control border border-current/25 px-1 text-[10px] font-medium opacity-60">
              {key}
            </kbd>
          </span>
        </button>
      ))}
    </div>
  );
}
