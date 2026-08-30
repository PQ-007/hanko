import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";

// The first route in this codebase to need a service-role client. Every
// other write in the app happens as the calling user's own identity, scoped
// by RLS (see bearer.ts) — that pattern doesn't work here because
// distractor_cache holds shared, non-user-owned reference data with no
// insert/update policy for authenticated clients at all (see
// 0015_distractor_cache.sql's comment: any signed-in user's own token being
// able to write there would let a hostile client poison shared quiz data for
// everyone). This key bypasses RLS entirely and must never be sent to a
// browser or logged — only ever used server-side, only for this one cache.
//
// Returns null rather than throwing if unconfigured, so a dev who hasn't set
// up the key yet gets a working app with an unwarmed cache, not a crash —
// the caller falls back to serving Jisho results without persisting them.
export function serviceClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createSupabaseClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
