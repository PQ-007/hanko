"use client";

import { useCallback, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import type { Word } from "@/lib/types";
import { computeNextReview, type Rating } from "@/lib/srs";
import { supabase } from "../../_lib/db";
import { T } from "../../_lib/strings";
import PracticeCard from "./PracticeCard";
import RatingButtons from "./RatingButtons";
import SessionComplete from "./SessionComplete";

export default function PracticeSession() {
  const params = useSearchParams();
  const deckId = params.get("deck");

  const [queue, setQueue] = useState<Word[] | null>(null);
  const [revealed, setRevealed] = useState(false);
  const [reviewedCount, setReviewedCount] = useState(0);

  const load = useCallback(async () => {
    let query = supabase
      .from("words")
      .select("*")
      .eq("deleted", false)
      .lte("due_at", new Date().toISOString())
      .order("due_at", { ascending: true })
      .limit(20);
    if (deckId) query = query.eq("deck_id", deckId);
    const { data } = await query;
    setQueue((data as Word[]) ?? []);
  }, [deckId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  if (queue === null) {
    return <p className="p-8 text-center text-sm text-gray-500">{T.loadingWords}</p>;
  }

  if (queue.length === 0) {
    if (reviewedCount > 0) return <SessionComplete count={reviewedCount} />;
    return (
      <div className="mx-auto max-w-md p-8 text-center">
        <div className="rounded-lg border border-dashed border-gray-300 bg-white p-10 text-gray-500">
          {T.noWordsDue}
        </div>
        <Link
          href="/decks"
          className="mt-4 inline-block text-sm font-medium text-gray-700 underline"
        >
          {T.backToDecks}
        </Link>
      </div>
    );
  }

  const word = queue[0];

  async function rate(rating: Rating) {
    const next = computeNextReview(word, rating);
    await supabase.from("words").update(next).eq("id", word.id);
    setReviewedCount((c) => c + 1);
    setRevealed(false);
    setQueue((prev) => {
      const rest = prev!.slice(1);
      return rating === "again" ? [...rest, word] : rest;
    });
  }

  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-6 p-6">
      <p className="text-sm text-gray-400">{queue.length}</p>
      <PracticeCard word={word} revealed={revealed} onReveal={() => setRevealed(true)} />
      <RatingButtons revealed={revealed} onRate={rate} />
    </div>
  );
}
