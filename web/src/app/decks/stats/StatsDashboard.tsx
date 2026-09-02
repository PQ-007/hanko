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
import WordSpotlight from "../_components/WordSpotlight";
import ReviewModeModal from "../_components/ReviewModeModal";
import QuickAddWordModal from "../_components/QuickAddWordModal";
import LoadingScene from "../review/battle/_components/LoadingScene";

// One SRS day's review count, from the review_activity() RPC (migration 0013).
// The server buckets by the user's day cutoff — the same boundary the scheduler
// uses — rather than by local midnight. That matters: grouping at midnight put
// a 01:00 review on a new streak day while the review queue still considered it
// yesterday, and it made mobile's streak a second, subtly different answer.
interface ActivityRow {
  day: string; // YYYY-MM-DD, already in the user's timezone
  reviews: number;
}

// What a session started right now would actually serve, per due_summary()
// (migration 0011) — the day cutoff and the per-day caps applied server-side,
// so this tile can't disagree with the practice screen.
interface DueSummary {
  due_now: number;
  review_due: number;
  new_due: number;
  review_remaining: number;
  new_remaining: number;
}

export default function StatsDashboard() {
  const router = useRouter();
  const [decks, setDecks] = useState<DeckWithCount[]>([]);
  const [words, setWords] = useState<Word[]>([]);
  const [reviews, setReviews] = useState<ActivityRow[] | null>(null);
  const [freezes, setFreezes] = useState(0);
  // The scheduler's today, from current_srs_day() (0019). Null until it lands
  // or if the RPC is missing, in which case currentStreak falls back to the
  // device's date — the behaviour this replaced.
  const [srsToday, setSrsToday] = useState<string | null>(null);
  const [due, setDue] = useState<DueSummary | null>(null);
  // True when review_log isn't there yet (migration 0005 not applied), so the
  // heatmap is running on the approximate last_reviewed_at fallback.
  const [logMissing, setLogMissing] = useState(false);
  const [loading, setLoading] = useState(true);
  // Which dialog, if any, is open. Both are mounted below the page rather
  // than inside the hero so a reload triggered by one can't unmount it.
  const [modal, setModal] = useState<"review" | "add" | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [decksRes, wordsRes, logRes, dueRes, todayRes, freezeRes] = await Promise.all([
      supabase.from("decks").select("*").eq("deleted", false).order("name"),
      supabase.from("words").select("*").eq("deleted", false),
      // Bucketed server-side by SRS day. The RPC also excludes undone answers
      // and battle/drill sources, so activity can't be inflated by answers the
      // user took back or by gamified modes.
      supabase.rpc("review_activity", { p_days: 400 }),
      supabase.rpc("due_summary"),
      // Cheap, and it decides which day the streak walk starts on. Bundled
      // into the same Promise.all so it costs no extra round trip.
      supabase.rpc("current_srs_day"),
      // profiles.streak_freezes (0014_gamification.sql). A missing column
      // (migration not applied) or missing row degrades to 0 rather than
      // failing the whole dashboard load.
      supabase.from("profiles").select("streak_freezes").maybeSingle(),
    ]);

    // Falls back to the client-side count below if 0011 isn't applied yet.
    const dueRows = dueRes.data as DueSummary[] | null;
    setDue(dueRes.error ? null : (dueRows?.[0] ?? null));

    setSrsToday(todayRes.error ? null : ((todayRes.data as string | null) ?? null));

    const freezeRow = freezeRes.data as { streak_freezes: number } | null;
    setFreezes(freezeRes.error ? 0 : (freezeRow?.streak_freezes ?? 0));

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
      setReviews((logRes.data as ActivityRow[]) ?? []);
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
      // Already one row per SRS day, keyed YYYY-MM-DD in the user's timezone —
      // no client-side date bucketing, which is what used to disagree with the
      // scheduler's 4am cutoff.
      for (const r of reviews) map.set(r.day, r.reviews);
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
    return <LoadingScene label={T.loadingStats} />;
  }

  const now = new Date();
  // Prefer the server's answer: it applies the day cutoff and the daily caps,
  // so the tile matches what the practice session will actually hand you. The
  // client-side count is the pre-0011 fallback.
  const backlog = words.filter((w) => new Date(w.due_at) <= now).length;
  const dueToday = due ? due.due_now : backlog;
  const heldBack = due ? due.review_due + due.new_due - due.due_now : 0;
  const mastered = words.filter((w) => {
    const g = gradeFor(w);
    return g === "A" || g === "B";
  }).length;
  const masteredPct = words.length === 0 ? 0 : Math.round((mastered / words.length) * 100);

  const activeDays = new Set(activity.keys());
  const streak = currentStreak(activeDays, freezes, srsToday ?? undefined);
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
        freezesAvailable={freezes}
        onPractice={() => setModal("review")}
        onAddWord={() => setModal("add")}
      />

      {logMissing && (
        <p className="flex items-center gap-2 rounded-control border border-line bg-paper-dim px-4 py-2.5 text-xs text-ink">
          <AlertCircle size={15} className="shrink-0" />
          {T.migrationHint}
        </p>
      )}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        <StatTile icon={BookMarked} label={T.statTotalWords} value={words.length} />
        <StatTile icon={Layers} label={T.statTotalDecks} value={decks.length} />
        <StatTile
          icon={CalendarCheck}
          label={T.statDueToday}
          value={dueToday}
          // When the daily cap holds cards back, say so — otherwise the tile
          // and the deck breakdown below look like they contradict each other.
          sub={heldBack > 0 ? T.dueHeldBack(heldBack) : undefined}
        />
        <StatTile
          icon={Sparkles}
          label={T.statMastered}
          value={mastered}
          sub={words.length > 0 ? `${masteredPct}%` : undefined}
        />
        <StatTile icon={Repeat} label={T.reviewsThisWeek} value={reviewsThisWeek} />
      </div>

      {/* srsToday, not the device date, so the word of the day turns over at
          the same moment the scheduler's day does. */}
      <WordSpotlight words={words} decks={decks} dayKey={srsToday} />

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

      {modal === "review" && (
        <ReviewModeModal
          onClose={() => setModal(null)}
          wordCount={words.length}
          dueNow={dueToday}
        />
      )}
      {modal === "add" && (
        <QuickAddWordModal
          decks={decks}
          onClose={(added) => {
            setModal(null);
            // Only on dismissal, and only if something changed: load() swaps
            // the page for its loading scene, which would take the dialog with
            // it if it ran after every word.
            if (added > 0) load();
          }}
        />
      )}
    </div>
  );
}
