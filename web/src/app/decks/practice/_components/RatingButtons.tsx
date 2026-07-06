"use client";

import type { Rating } from "@/lib/srs";
import { T } from "../../_lib/strings";

export default function RatingButtons({
  revealed,
  onRate,
}: {
  revealed: boolean;
  onRate: (rating: Rating) => void;
}) {
  if (!revealed) return null;

  return (
    <div className="grid w-full grid-cols-4 gap-2">
      <button
        onClick={() => onRate("again")}
        className="rounded border border-red-200 px-3 py-2 text-sm font-medium text-red-700 transition hover:bg-red-50"
      >
        {T.again}
      </button>
      <button
        onClick={() => onRate("hard")}
        className="rounded border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
      >
        {T.hard}
      </button>
      <button
        onClick={() => onRate("good")}
        className="rounded border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
      >
        {T.good}
      </button>
      <button
        onClick={() => onRate("easy")}
        className="rounded bg-gray-900 px-3 py-2 text-sm font-medium text-white transition hover:bg-gray-800"
      >
        {T.easy}
      </button>
    </div>
  );
}
