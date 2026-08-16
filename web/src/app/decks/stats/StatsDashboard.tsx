"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { AlertCircle, BookMarked, CalendarCheck, Layers, Repeat, Sparkles } from "lucide-react";
import type { Deck, DeckWithCount, Word } from "@/lib/types";
import { gradeFor } from "@/lib/srs";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { addDays, currentStreak, localDateKey, longestStreak, startOfDay } from "../_lib/dates";
import StatTile from "../_components/StatTile";
import StreakHero from "../_components/StreakHero";
import ActivityHeatmap from "../_components/ActivityHeatmap";
import GrowthChart from "../_components/GrowthChart";
import GradeChart from "../_components/GradeChart";
import WeekdayReviewsChart from "../_components/WeekdayReviewsChart";
import DeckBreakdownTable from "../_components/DeckBreakdownTable";

interface ReviewLogRow {
  reviewed_at: string;
}

export default function StatsDashboard() {
  const router = useRouter();
  const [decks, setDecks] = useState<DeckWithCount[]>([]);
  const [words, setWords] = useState<Word[]>([]);
  const [reviews, setReviews] = useState<ReviewLogRow[] | null>(null);
  // True when review_log isn't there yet (migration 0005 not applied), so the
  // heatmap is running on the approximate last_reviewed_at fallback.
  const [logMissing, setLogMissing] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const since = addDays(startOfDay(new Date()), -400).toISOString();
    const [decksRes, wordsRes, logRes] = await Promise.all([
      supabase.from("decks").select("*").eq("deleted", false).order("name"),
      supabase.from("words").select("*").eq("deleted", false),
      // Only real reviews count toward streaks and the heatmap: answers the
      // user took back (undone) and future battle/drill answers are logged but
      // must not inflate activity. See 0008_review_log_v2.sql.
      supabase
        .from("review_log")
        .select("reviewed_at")
        .eq("undone", false)
        .eq("source", "review")
        .gte("reviewed_at", since),
    ]);

    const wordRows = (wordsRes.data as Word[]) ?? [];
    const counts = new Map<string, number>();
    wordRows.forEach((w) => counts.set(w.deck_id, (counts.get(w.deck_id) ?? 0) + 1));
    setDecks(
      ((decksRes.data as Deck[]) ?? []).map((d) => ({ ...d, word_count: counts.get(d.id) ?? 0 }))
    );
    setWords(wordRows);

    if (logRes.error) {
      setLogMissing(true);
      setReviews(null);
    } else {
      setLogMissing(false);
      setReviews((logRes.data as ReviewLogRow[]) ?? []);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  // Reviews per local calendar day. Prefers the real log; falls back to each
  // word's most recent review, which undercounts history but keeps the
  // calendar meaningful before the migration is applied.
  const activity = useMemo(() => {
    const map = new Map<string, number>();
    if (reviews) {
      for (const r of reviews) {
        const k = localDateKey(new Date(r.reviewed_at));
        map.set(k, (map.get(k) ?? 0) + 1);
      }
    } else {
      for (const w of words) {
        if (!w.last_reviewed_at) continue;
        const k = localDateKey(new Date(w.last_reviewed_at));
        map.set(k, (map.get(k) ?? 0) + 1);
      }
    }
    return map;
  }, [reviews, words]);

  // Words added per local calendar day — always exact, since date_added is
  // stamped once per word and never overwritten.
  const addedActivity = useMemo(() => {
    const map = new Map<string, number>();
    for (const w of words) {
      const k = localDateKey(new Date(w.date_added));
      map.set(k, (map.get(k) ?? 0) + 1);
    }
    return map;
  }, [words]);

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

  const activeDays = new Set(activity.keys());
  const streak = currentStreak(activeDays);
  const best = Math.max(streak, longestStreak(activeDays));

  const todayKey = localDateKey(now);
  const addedToday = words.filter((w) => localDateKey(new Date(w.date_added)) === todayKey).length;

  const weekStart = addDays(startOfDay(now), -6);
  let reviewsThisWeek = 0;
  for (let i = 0; i < 7; i++) {
    reviewsThisWeek += activity.get(localDateKey(addDays(weekStart, i))) ?? 0;
  }

  return (
    <div className="mx-auto flex max-w-[1700px] flex-col gap-4 p-4 sm:px-8 sm:py-6">
      <StreakHero
        streak={streak}
        bestStreak={best}
        addedToday={addedToday}
        masteredPct={masteredPct}
      />

      {logMissing && (
        <p className="flex items-center gap-2 rounded-lg border border-gray-300 bg-gray-100 px-4 py-2.5 text-xs text-gray-700">
          <AlertCircle size={15} className="shrink-0" />
          {T.migrationHint}
        </p>
      )}

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
        <StatTile icon={Repeat} label={T.reviewsThisWeek} value={reviewsThisWeek} />
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <ActivityHeatmap counts={activity} title={T.heatmapTitle} formatCount={T.reviewsN} />
        <ActivityHeatmap
          counts={addedActivity}
          title={T.addedHeatmapTitle}
          formatCount={T.wordsN}
        />
      </div>

      {words.length > 0 && (
        <>
          <GrowthChart words={words} />
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            <GradeChart words={words} title={T.overallGradeTitle} />
            <WeekdayReviewsChart counts={activity} />
          </div>
        </>
      )}

      <DeckBreakdownTable
        decks={decks}
        words={words}
        onSelectDeck={(id) => router.push(`/decks?deck=${id}`)}
      />
    </div>
  );
}
