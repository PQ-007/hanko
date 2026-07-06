import { createClient } from "@/lib/supabase/server";
import type { Deck, Word } from "@/lib/types";

export { sanitizeFilename, sanitizeTag, frontText, backText } from "@/lib/wordText";

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
