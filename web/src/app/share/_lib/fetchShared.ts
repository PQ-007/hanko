import { cache } from "react";
import { createClient } from "@supabase/supabase-js";
import type { SharedDeck } from "./trial";

/** Tokens are 32 hex characters (0028); anything else is never looked up. */
export function isShareToken(token: string): boolean {
  return /^[0-9a-f]{32}$/.test(token);
}

/**
 * A shared deck, read as an anonymous caller through shared_deck() — no
 * session cookies, so the page and its preview image see exactly what a
 * signed-out visitor sees. Cached per request (page + metadata share it).
 */
export const fetchSharedDeck = cache(async (token: string): Promise<SharedDeck | null> => {
  if (!isShareToken(token)) return null;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  const supabase = createClient(url, key, { auth: { persistSession: false } });
  const { data, error } = await supabase.rpc("shared_deck", { p_token: token });
  if (error || !data) return null;
  const deck = data as SharedDeck;
  return { name: deck.name, words: Array.isArray(deck.words) ? deck.words : [] };
});
