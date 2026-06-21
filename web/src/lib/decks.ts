import { createClient } from "@/lib/supabase/server";
import type { Deck, Word } from "@/lib/types";

// Loads a deck and its (non-deleted) words for the current user. RLS ensures a
// user can only ever read their own deck, so an unauthorized id simply returns
// null. Used by the export and audio routes.
export async function loadDeckWithWords(
  deckId: string
): Promise<{ deck: Deck; words: Word[] } | null> {
  const supabase = await createClient();

  const { data: deck } = await supabase
    .from("decks")
    .select("*")
    .eq("id", deckId)
    .eq("deleted", false)
    .single();
  if (!deck) return null;

  const { data: words } = await supabase
    .from("words")
    .select("*")
    .eq("deck_id", deckId)
    .eq("deleted", false)
    .order("date_added", { ascending: true });

  return { deck: deck as Deck, words: (words as Word[]) ?? [] };
}

export function sanitizeFilename(name: string): string {
  return name.replace(/[^a-z0-9-_]+/gi, "_").slice(0, 60) || "deck";
}

export function sanitizeTag(name: string): string {
  return name.replace(/\s+/g, "_").replace(/[^\w-]/g, "");
}

// Front field text: "term (reading)" when the reading adds information.
export function frontText(word: Word): string {
  return word.reading && word.reading !== word.term
    ? `${word.term} (${word.reading})`
    : word.term;
}
