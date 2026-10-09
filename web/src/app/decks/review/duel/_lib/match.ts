// A row of `matches` as the duel screens use it (0020, 0030).

export interface MatchRow {
  id: string;
  join_code: string | null;
  host_id: string;
  guest_id: string | null;
  invited_id: string | null;
  rematch_of: string | null;
  host_character: string;
  guest_character: string | null;
  host_baseline_ms: number | null;
  guest_baseline_ms: number | null;
  status: string;
  round_count: number;
  /** The question set both players answer (0030); null on older matches. */
  questions: unknown;
}

/** A challenge waiting for me — duel_invites() (0030). */
export interface DuelInvite {
  match_id: string;
  host_id: string;
  host_name: string | null;
  host_handle: string | null;
  host_image: string | null;
  rematch: boolean;
  created_at: string;
}

/** Who I'm fighting — duel_opponent() (0030). Name and picture are friends only. */
export interface DuelOpponentInfo {
  opponent_id: string;
  handle: string | null;
  name: string | null;
  image: string | null;
  is_friend: boolean;
  elo: number;
  games: number;
}

export function opponentLabel(o: { name: string | null; handle: string | null } | null | undefined, fallback: string): string {
  return o?.name?.trim() || (o?.handle ? `@${o.handle}` : fallback);
}
