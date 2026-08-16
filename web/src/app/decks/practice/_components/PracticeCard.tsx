"use client";

import { useState } from "react";
import { Volume2 } from "lucide-react";
import { gradeFor } from "@/lib/srs";
import type { QueueCard } from "../../_lib/types";
import { supabase } from "../../_lib/db";
import { GRADE_COLOR } from "../../_lib/gradeColors";
import { T } from "../../_lib/strings";

// Review card. The prompt stays put and the answer opens beneath it, rather
// than flipping the card over — you can compare what you recalled against
// what was right, and a long meaning grows the card instead of being clipped
// by a fixed-height face.
export default function PracticeCard({
  card,
  revealed,
  onReveal,
}: {
  card: QueueCard;
  revealed: boolean;
  onReveal: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const grade = gradeFor(card);

  async function play(e: React.MouseEvent) {
    e.stopPropagation();
    let path = card.audio_path;
    if (!path) {
      setBusy(true);
      try {
        const res = await fetch(`/api/words/${card.word_id}/audio`, { method: "POST" });
        if (!res.ok) return;
        path = (await res.json()).audio_path as string;
      } finally {
        setBusy(false);
      }
    }
    if (!path) return;
    const { data } = await supabase.storage.from("word-audio").createSignedUrl(path, 60);
    if (data?.signedUrl) new Audio(data.signedUrl).play();
  }

  return (
    <div className="relative w-full overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
      {/* Mastery grade — a small dot in the same ramp the dashboard uses. */}
      <span className="absolute right-4 top-4 flex items-center gap-1.5 text-[11px] font-medium text-gray-400">
        <span
          style={{ backgroundColor: GRADE_COLOR[grade].fill }}
          className="h-2 w-2 rounded-full"
        />
        {grade === "new" ? T.gradeNew : grade}
      </span>

      <div className="flex min-h-[15rem] flex-col items-center justify-center px-6 py-10 text-center sm:min-h-[17rem]">
        <div className="text-5xl font-bold leading-tight tracking-tight text-gray-900 sm:text-6xl">
          {card.term}
        </div>

        {revealed ? (
          <div className="mt-3 flex animate-[fadeUp_240ms_ease-out] flex-col items-center gap-1">
            {card.reading && card.reading !== card.term && (
              <div className="flex items-center gap-2 text-base text-gray-500">
                {card.reading}
                <button
                  onClick={play}
                  disabled={busy}
                  title={T.playAudio}
                  className="rounded-full border border-gray-200 p-1.5 text-gray-500 transition hover:bg-gray-50 disabled:opacity-50"
                >
                  <Volume2 size={14} className={busy ? "animate-pulse" : ""} />
                </button>
              </div>
            )}
            {!card.reading && (
              <button
                onClick={play}
                disabled={busy}
                title={T.playAudio}
                className="rounded-full border border-gray-200 p-1.5 text-gray-500 transition hover:bg-gray-50 disabled:opacity-50"
              >
                <Volume2 size={14} className={busy ? "animate-pulse" : ""} />
              </button>
            )}
          </div>
        ) : (
          // A hint, not a second button — the primary reveal action sits
          // below the card, where the rating buttons will replace it.
          <button
            onClick={onReveal}
            className="mt-6 flex items-center gap-1.5 text-xs text-gray-400 transition hover:text-gray-600"
          >
            {T.showAnswer}
            <kbd className="rounded border border-gray-200 bg-gray-50 px-1.5 py-0.5 text-[10px] font-medium text-gray-400">
              {T.spaceHint}
            </kbd>
          </button>
        )}
      </div>

      {revealed && (
        <div className="animate-[fadeUp_260ms_ease-out] border-t border-gray-200 bg-gray-50 px-6 py-6 text-center">
          {card.meaning_mn && (
            <p className="text-xl font-semibold leading-snug text-gray-900">{card.meaning_mn}</p>
          )}
          {card.meaning && (
            <p className="mt-1.5 text-sm leading-snug text-gray-500">{card.meaning}</p>
          )}
          {!card.meaning_mn && !card.meaning && (
            <p className="text-sm text-gray-400">—</p>
          )}
        </div>
      )}
    </div>
  );
}
