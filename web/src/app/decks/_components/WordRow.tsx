"use client";

import { useState } from "react";
import { Pencil, Play, Trash2 } from "lucide-react";
import type { Word } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
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

  async function play() {
    let path = word.audio_path;
    if (!path) {
      setGenAudio(true);
      try {
        const res = await fetch(`/api/words/${word.id}/audio`, { method: "POST" });
        if (!res.ok) {
          alert((await res.json().catch(() => null))?.error ?? T.audioFailed);
          return;
        }
        path = (await res.json()).audio_path as string;
        onChanged();
      } finally {
        setGenAudio(false);
      }
    }
    if (!path) return;
    const { data } = await supabase.storage.from("word-audio").createSignedUrl(path, 60);
    if (data?.signedUrl) new Audio(data.signedUrl).play();
  }

  const playBtn = (
    <button
      onClick={play}
      disabled={genAudio}
      title={T.playAudio}
      className="shrink-0 rounded-full border border-gray-200 p-1.5 text-gray-500 transition hover:bg-gray-50 disabled:opacity-50"
    >
      <Play size={14} className={genAudio ? "animate-pulse" : ""} />
    </button>
  );
  const editBtn = (
    <button onClick={onEdit} title={T.edit} className="text-gray-300 transition hover:text-gray-900">
      <Pencil size={15} />
    </button>
  );
  const removeBtn = (
    <button onClick={remove} title={T.removeWord} className="text-gray-300 transition hover:text-gray-900">
      <Trash2 size={15} />
    </button>
  );

  // Card view (grid): a flashcard that flips on hover — front shows the term +
  // reading (the prompt), back reveals the Mongolian + English answer.
  if (grid) {
    return (
      <div className="group relative h-48 perspective-[1000px]">
        <div className="relative h-full w-full transform-3d transition-transform duration-500 group-hover:rotate-y-180">
          {/* Front — the prompt */}
          <div
            style={{ WebkitBackfaceVisibility: "hidden", backfaceVisibility: "hidden" }}
            className="absolute inset-0 flex flex-col items-center justify-center overflow-hidden rounded-xl border border-gray-200 bg-white p-4 text-center shadow-sm backface-hidden"
          >
            <GradeBadge word={word} />
            <div className="relative text-3xl font-bold leading-tight text-gray-900">{word.term}</div>
            {word.reading && <div className="relative mt-1.5 text-sm text-gray-400">{word.reading}</div>}
          </div>

          {/* Back — the answer (opaque so the front never shows through) */}
          <div
            style={{ WebkitBackfaceVisibility: "hidden", backfaceVisibility: "hidden" }}
            className="absolute inset-0 flex flex-col items-center overflow-hidden rounded-xl border border-gray-300 bg-gray-50 p-4 text-center shadow-sm backface-hidden rotate-y-180"
          >
            <GradeBadge word={word} />
            <div className="absolute right-2 top-2">{playBtn}</div>
            <div className="relative max-w-full min-w-0">
              <div className="truncate text-xl font-bold leading-tight text-gray-900">
                {word.term}
              </div>
              {word.reading && (
                <div className="truncate text-xs text-gray-400">{word.reading}</div>
              )}
            </div>
            <div className="relative mt-2 flex w-full flex-1 flex-col items-center overflow-hidden">
              {word.meaning_mn && (
                <div className="line-clamp-2 break-words text-sm font-semibold leading-snug text-gray-900">
                  {word.meaning_mn}
                </div>
              )}
              {word.meaning && (
                <div className="mt-1 line-clamp-2 break-words text-xs leading-snug text-gray-400">
                  {word.meaning}
                </div>
              )}
            </div>
            <div className="relative flex w-full justify-center gap-3 border-t border-gray-200 pt-2">
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
          {word.reading && <span className="text-sm text-gray-500">{word.reading}</span>}
        </div>
        {word.meaning && <div className="break-words text-sm text-gray-600">{word.meaning}</div>}
        {word.meaning_mn && (
          <div className="break-words text-sm text-gray-900">{word.meaning_mn}</div>
        )}
      </button>
      <div className="flex shrink-0 items-center gap-2 sm:opacity-0 sm:group-hover:opacity-100">
        {editBtn}
        {removeBtn}
      </div>
    </li>
  );
}
