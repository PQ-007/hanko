import type { SupabaseClient } from "@supabase/supabase-js";
import type { Deck, Word } from "@/lib/types";

export { sanitizeFilename, sanitizeTag, frontText, backText } from "@/lib/wordText";

// Loads a deck and its (non-deleted) words for the caller. Takes the client
// rather than building one, so a route can pass `clientForRequest()` and serve
// both the web's cookie session and the mobile app's Bearer token. RLS still
// scopes every read to that user, so an unauthorized id simply returns null.
export async function loadDeckWithWords(
  supabase: SupabaseClient,
  deckId: string
): Promise<{ deck: Deck; words: Word[] } | null> {
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
