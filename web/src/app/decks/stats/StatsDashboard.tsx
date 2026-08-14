"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { BookMarked, CalendarCheck, Flame, Layers, Sparkles } from "lucide-react";
import type { Deck, DeckWithCount, Word } from "@/lib/types";
import { gradeFor } from "@/lib/srs";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import StatTile from "../_components/StatTile";
import GradeChart from "../_components/GradeChart";
import UpcomingReviewsChart from "../_components/UpcomingReviewsChart";
import DeckBreakdownTable from "../_components/DeckBreakdownTable";

// Local calendar date (not UTC — Mongolia is UTC+8, so slicing an ISO string
// would shift local midnight back to the previous day).
function localDateKey(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// Current consecutive-day review streak: walk backwards from today (or from
// yesterday if today has no review yet, so a streak stays "alive" until the
// day is over) while each day has at least one reviewed word.
function computeStreak(reviewedDateKeys: Set<string>): number {
  const cursor = new Date();
  cursor.setHours(0, 0, 0, 0);
  if (!reviewedDateKeys.has(localDateKey(cursor))) {
    cursor.setDate(cursor.getDate() - 1);
  }
  let streak = 0;
  while (reviewedDateKeys.has(localDateKey(cursor))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

export default function StatsDashboard() {
  const router = useRouter();
  const [decks, setDecks] = useState<DeckWithCount[]>([]);
  const [words, setWords] = useState<Word[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const [{ data: deckRows }, { data: wordRows }] = await Promise.all([
      supabase.from("decks").select("*").eq("deleted", false).order("name"),
      supabase.from("words").select("*").eq("deleted", false),
    ]);
    const counts = new Map<string, number>();
    (wordRows ?? []).forEach((w: Word) => counts.set(w.deck_id, (counts.get(w.deck_id) ?? 0) + 1));
    const withCounts: DeckWithCount[] = ((deckRows as Deck[]) ?? []).map((d) => ({
      ...d,
      word_count: counts.get(d.id) ?? 0,
    }));
    setDecks(withCounts);
    setWords((wordRows as Word[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  if (loading) {
    return <p className="p-8 text-center text-sm text-gray-500">{T.loadingStats}</p>;
  }

  const now = new Date();
  const dueToday = words.filter((w) => new Date(w.due_at) <= now).length;
  const mastered = words.filter((w) => {
    const g = gradeFor(w);
    return g === "A" || g === "B";
  }).length;
  const masteredPct = words.length === 0 ? 0 : Math.round((mastered / words.length) * 100);

  const weekAgo = new Date(now);
  weekAgo.setDate(weekAgo.getDate() - 7);
  const newThisWeek = words.filter((w) => new Date(w.date_added) >= weekAgo).length;

  const reviewedDateKeys = new Set(
    words.filter((w) => w.last_reviewed_at).map((w) => localDateKey(new Date(w.last_reviewed_at as string)))
  );
  const streak = computeStreak(reviewedDateKeys);

  return (
    <div className="mx-auto flex max-w-[1700px] flex-col gap-4 p-4 sm:px-8 sm:py-6">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <StatTile icon={BookMarked} label={T.statTotalWords} value={words.length} />
        <StatTile icon={Layers} label={T.statTotalDecks} value={decks.length} />
        <StatTile icon={CalendarCheck} label={T.statDueToday} value={dueToday} />
        <StatTile
          icon={Sparkles}
          label={T.statMastered}
          value={mastered}
          sub={words.length > 0 ? `${masteredPct}%` : undefined}
        />
        <StatTile
          icon={Flame}
          label={T.statStreak}
          value={T.streakDays(streak)}
          sub={T.statNewWeek(newThisWeek)}
        />
      </div>

      {words.length > 0 && (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <GradeChart words={words} title={T.overallGradeTitle} />
          <UpcomingReviewsChart words={words} />
        </div>
      )}

      <DeckBreakdownTable
        decks={decks}
        words={words}
        onSelectDeck={(id) => router.push(`/decks?deck=${id}`)}
      />
    </div>
  );
}
