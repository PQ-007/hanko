import { supabase } from "../../../_lib/db";
import { headToHead, type HeadToHead, type MatchRow as FinishedRow } from "../../../_lib/social";

// Your face-to-face record with one opponent: every finished or abandoned
// match the two of you played, tallied by headToHead() (the same tally the
// friends page uses). RLS already limits `matches` to yours, so asking for
// both directions of the pairing is all the filtering this needs.

export const EMPTY_RECORD: HeadToHead = { wins: 0, losses: 0, draws: 0, matches: [] };

export function recordTotal(r: HeadToHead): number {
  return r.wins + r.losses + r.draws;
}

/** Oldest → newest, the last [n] results — the little W L W W L strip. */
export function lastResults(r: HeadToHead, n = 5): HeadToHead["matches"] {
  return r.matches.slice(0, n).reverse();
}

export async function loadRecord(me: string, other: string): Promise<HeadToHead> {
  const { data, error } = await supabase
    .from("matches")
    .select("id, host_id, guest_id, status, winner_id, host_hp, guest_hp, created_at, finished_at")
    .or(`and(host_id.eq.${me},guest_id.eq.${other}),and(host_id.eq.${other},guest_id.eq.${me})`)
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) return EMPTY_RECORD;
  return headToHead((data as FinishedRow[]) ?? [], me).get(other) ?? EMPTY_RECORD;
}
