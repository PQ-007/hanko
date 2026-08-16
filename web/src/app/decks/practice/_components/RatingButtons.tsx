"use client";

import { previewNext, type Rating } from "@/lib/srs";
import type { QueueCard } from "../../_lib/types";
import { formatPreview } from "../../_lib/interval";
import { T } from "../../_lib/strings";

// Each button states what it will cost you: the label, the resulting interval
// ("6 өдөр"), and its number key. Tone is carried by a tint plus the label
// text, never by color alone.
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
    className: "border-gray-900 bg-gray-900 text-white hover:bg-gray-800",
  },
  {
    rating: "easy",
    key: "4",
    label: T.easy,
    className: "border-emerald-200 bg-emerald-50/60 text-emerald-800 hover:bg-emerald-100",
  },
];

export default function RatingButtons({
  card,
  onRate,
}: {
  card: QueueCard;
  onRate: (rating: Rating) => void;
}) {
  return (
    <div className="grid w-full grid-cols-2 gap-2 sm:grid-cols-4">
      {OPTIONS.map(({ rating, key, label, className }) => {
        // Every button states its real consequence, including the minute-scale
        // ones: a card still in the learning steps comes back in minutes, so
        // labelling that "1 өдөр" would be a lie.
        const preview = formatPreview(previewNext(card, rating));
        return (
          <button
            key={rating}
            onClick={() => onRate(rating)}
            className={`flex flex-col items-center gap-0.5 rounded-lg border px-3 py-2.5 transition ${className}`}
          >
            <span className="flex items-center gap-1.5 text-sm font-semibold">
              {label}
              <kbd className="rounded border border-current/25 px-1 text-[10px] font-medium opacity-60">
                {key}
              </kbd>
            </span>
            <span className="text-[11px] opacity-75">{preview}</span>
          </button>
        );
      })}
    </div>
  );
}
