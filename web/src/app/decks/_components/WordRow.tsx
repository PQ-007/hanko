"use client";

import { useState } from "react";
import { Pencil, Play, Trash2 } from "lucide-react";
import type { Word } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { playWordAudio } from "../_lib/audio";
import GradeBadge from "./GradeBadge";

export default function WordRow({
  word,
  grid = false,
  onEdit,
  onChanged,
}: {
  word: Word;
  grid?: boolean;
  onEdit: () => void;
  onChanged: () => void;
}) {
  const [genAudio, setGenAudio] = useState(false);

  async function remove() {
    await supabase.from("words").update({ deleted: true }).eq("id", word.id);
    onChanged();
  }

  // Busy for the whole call now, not just the generation half: the signed-URL
  // round trip was previously unguarded, so a double click there fired two
  // plays.
  async function play() {
    setGenAudio(true);
    try {
      const path = await playWordAudio(word);
      // Newly generated — the row this was rendered from is now stale.
      if (path && path !== word.audio_path) onChanged();
    } finally {
      setGenAudio(false);
    }
  }

  const playBtn = (
    <button
      onClick={play}
      disabled={genAudio}
      title={T.playAudio}
      className="shrink-0 rounded-full border border-line-soft p-1.5 text-ink-soft transition hover:bg-paper-dim disabled:opacity-50"
    >
      <Play size={14} className={genAudio ? "animate-pulse" : ""} />
    </button>
  );
  const editBtn = (
    <button onClick={onEdit} title={T.edit} className="text-ink-mute transition hover:text-ink">
      <Pencil size={15} />
    </button>
  );
  const removeBtn = (
    <button onClick={remove} title={T.removeWord} className="text-ink-mute transition hover:text-ink">
      <Trash2 size={15} />
    </button>
  );

  // Card view (grid): a flashcard that turns on hover (or keyboard focus —
  // the answer side's buttons are focusable) — front shows the term +
  // reading (the prompt), back reveals the Mongolian + English answer.
  // The 3D mechanics live in .hk-flip* in globals.css; see the note there for
  // why they are a component and not a stack of utilities.
  if (grid) {
    return (
      <div className="hk-flip h-48">
        <div className="hk-flip-inner">
          {/* Front — the prompt */}
          <div className="hk-flip-face flex flex-col items-center justify-center border border-line-soft bg-white p-4 text-center">
            <GradeBadge word={word} />
            <div className="relative text-3xl font-bold leading-tight text-ink">{word.term}</div>
            {word.reading && <div className="relative mt-1.5 text-sm text-ink-mute">{word.reading}</div>}
          </div>

          {/* Back — the answer (opaque so the front never shows through) */}
          <div className="hk-flip-face hk-flip-back flex flex-col items-center border border-line bg-paper p-4 text-center">
            <GradeBadge word={word} />
            <div className="absolute right-2 top-2">{playBtn}</div>
            <div className="relative max-w-full min-w-0">
              <div className="truncate text-xl font-bold leading-tight text-ink">
                {word.term}
              </div>
              {word.reading && (
                <div className="truncate text-xs text-ink-mute">{word.reading}</div>
              )}
            </div>
            <div className="relative mt-2 flex w-full flex-1 flex-col items-center overflow-hidden">
              {word.meaning_mn && (
                <div className="line-clamp-2 break-words text-sm font-semibold leading-snug text-ink">
                  {word.meaning_mn}
                </div>
              )}
              {word.meaning && (
                <div className="mt-1 line-clamp-2 break-words text-xs leading-snug text-ink-mute">
                  {word.meaning}
                </div>
              )}
            </div>
            <div className="relative flex w-full justify-center gap-3 border-t border-line-soft pt-2">
              {editBtn}
              {removeBtn}
            </div>
          </div>
        </div>
      </div>
    );
  }

  // List view (compact row).
  return (
    <li className="group flex items-center gap-3 px-4 py-2">
      {playBtn}
      <button onClick={onEdit} className="min-w-0 flex-1 text-left" title={T.edit}>
        <div className="flex items-baseline gap-2">
          <span className="font-medium">{word.term}</span>
          {word.reading && <span className="text-sm text-ink-soft">{word.reading}</span>}
        </div>
        {word.meaning && <div className="break-words text-sm text-ink-soft">{word.meaning}</div>}
        {word.meaning_mn && (
          <div className="break-words text-sm text-ink">{word.meaning_mn}</div>
        )}
      </button>
      <div className="flex shrink-0 items-center gap-2 sm:opacity-0 sm:group-hover:opacity-100">
        {editBtn}
        {removeBtn}
      </div>
    </li>
  );
}
