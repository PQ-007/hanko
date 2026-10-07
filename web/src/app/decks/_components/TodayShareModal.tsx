"use client";

import { useEffect, useState } from "react";
import { X } from "@/ui/icons";
import { supabase } from "../_lib/db";
import { formatDateMn } from "../_lib/dates";
import { T } from "../_lib/strings";
import { STORY_MAX_WORDS, type StoryCard } from "../_lib/storyCard";
import StoryImagePanel from "./StoryImagePanel";

interface Today {
  day: string;
  answers: number;
  recalled: number;
  added: number;
  words: { term: string; reading: string | null; meaning: string | null; meaning_mn: string | null }[];
}

/** "Today's words" as a story image — share_today() (0028), the SRS day's recalls. */
export default function TodayShareModal({ streak, onClose }: { streak: number; onClose: () => void }) {
  const [today, setToday] = useState<Today | null | "failed">(null);

  useEffect(() => {
    supabase.rpc("share_today", { p_limit: 50 }).then(({ data, error }) => {
      setToday(error || !data ? "failed" : (data as Today));
    });
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  let card: StoryCard | null = null;
  if (today && today !== "failed" && today.words.length > 0) {
    const [y, m, d] = today.day.split("-").map(Number);
    card = {
      kicker: formatDateMn(new Date(y, m - 1, d)),
      heading: T.storyTodayHeading,
      stats: T.storyTodayStats(today.recalled, today.added),
      badge: streak > 1 ? T.storyStreak(streak) : undefined,
      words: today.words.slice(0, STORY_MAX_WORDS).map((w) => ({
        term: w.term,
        reading: w.reading,
        meaning: w.meaning_mn || w.meaning,
      })),
      total: today.recalled,
      moreLabel: T.storyMore,
      footer: "",
    };
  }

  return (
    <div
      onClick={onClose}
      role="dialog"
      aria-modal
      aria-label={T.shareTodayTitle}
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/40 p-4"
    >
      <div onClick={(e) => e.stopPropagation()} className="my-auto w-full max-w-sm rounded-card bg-paper p-5 shadow-2xl">
        <div className="flex items-start justify-between gap-4">
          <h2 className="text-lg font-semibold text-ink">{T.shareTodayTitle}</h2>
          <button
            onClick={onClose}
            title={T.closeLabel}
            aria-label={T.closeLabel}
            className="shrink-0 rounded-control p-1 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
          >
            <X size={18} />
          </button>
        </div>
        <div className="mt-4">
          {today === null ? (
            <p className="py-10 text-center text-sm text-ink-mute">…</p>
          ) : today === "failed" ? (
            <p className="py-6 text-center text-sm text-red-700">{T.shareFailed}</p>
          ) : card ? (
            <StoryImagePanel card={card} fileName={`words-${today.day}`} />
          ) : (
            <p className="py-6 text-center text-sm text-ink-soft">{T.shareTodayEmpty}</p>
          )}
        </div>
      </div>
    </div>
  );
}
