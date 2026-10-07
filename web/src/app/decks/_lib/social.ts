// Friends, XP and ELO (0026_social.sql) — the web half of mobile's
// social_api.dart. Everything about another person comes from
// friend_overview(), which decides on the server whose numbers a caller may
// see; nothing here queries anyone else's tables.

/** One row of friend_overview(): you or an accepted friend. Numbers are null
 *  for a friend who turned sharing off. */
export interface FriendRow {
  user_id: string;
  handle: string | null;
  name: string | null;
  image: string | null;
  is_me: boolean;
  shares: boolean;
  elo: number | null;
  pvp_games: number | null;
  xp_total: number | null;
  xp_week: number | null;
  added_today: number | null;
  reviewed_today: number | null;
  words_learned: number | null;
  kanji_learned: number | null;
  recent_kanji: string[] | null;
  active_days_week: number | null;
}

export interface FriendRequest {
  other_id: string;
  handle: string | null;
  name: string | null;
  image: string | null;
  incoming: boolean;
}

/** One row of global_leaderboard() (0027): handle and scores only — a
 *  stranger's name, picture and activity are never sent. */
export interface GlobalRow {
  rank: number;
  handle: string;
  is_me: boolean;
  is_friend: boolean;
  xp_total: number;
  xp_week: number;
  elo: number;
}

export type SendResult = "sent" | "accepted" | "already" | "not_found" | "self";

/**
 * Levels grow with the square root of XP (level 2 at 100, 5 at 1,600, 10 at
 * 8,100). Same curve as mobile's levelFor in social_api.dart — both are
 * pinned by the same cases in their tests.
 */
export function levelFor(xp: number): number {
  return Math.floor(Math.sqrt(Math.max(0, xp) / 100)) + 1;
}

/** XP where a level starts, for the progress bar. */
export function xpForLevel(level: number): number {
  return 100 * (level - 1) * (level - 1);
}

/** 3–20 of a-z, 0-9, _ — the profiles_handle_format check, client side. */
export function normalizeHandle(raw: string): string | null {
  const h = raw.trim().replace(/^@/, "").toLowerCase();
  return /^[a-z0-9_]{3,20}$/.test(h) ? h : null;
}

export function displayName(r: Pick<FriendRow, "name" | "handle">): string {
  return r.name?.trim() || r.handle || "—";
}

export type RankBy = "week" | "total" | "elo";

/** The leaderboard: only people whose numbers are shared can be ranked. */
export function rankFriends(rows: FriendRow[], by: RankBy): FriendRow[] {
  const score = (r: FriendRow) =>
    by === "week" ? (r.xp_week ?? 0) : by === "total" ? (r.xp_total ?? 0) : (r.elo ?? 1000);
  return rows.filter((r) => r.shares).sort((a, b) => score(b) - score(a));
}

// ---- Online duels between friends ------------------------------------------

/** The columns of a match the head-to-head needs (RLS: your own matches only). */
export interface MatchRow {
  id: string;
  host_id: string;
  guest_id: string | null;
  host_hp: number;
  guest_hp: number;
  winner_id: string | null;
  status: string;
  finished_at: string | null;
  created_at: string;
}

export type MatchResult = "win" | "loss" | "draw";

export interface MatchSummary {
  id: string;
  result: MatchResult;
  myHp: number;
  theirHp: number;
  /** Ended by someone leaving (concede/forfeit) rather than played out. */
  abandoned: boolean;
  at: string;
}

export interface HeadToHead {
  wins: number;
  losses: number;
  draws: number;
  /** Newest first. */
  matches: MatchSummary[];
}

/**
 * Your record against each opponent, from your finished/abandoned matches.
 * A match with no winner counts as a draw; lobbies and live matches don't
 * count. Keyed by the opponent's user id.
 */
export function headToHead(rows: MatchRow[], me: string): Map<string, HeadToHead> {
  const out = new Map<string, HeadToHead>();
  const done = rows
    .filter((m) => (m.status === "finished" || m.status === "abandoned") && m.guest_id)
    .sort((a, b) => (b.finished_at ?? b.created_at).localeCompare(a.finished_at ?? a.created_at));
  for (const m of done) {
    const iAmHost = m.host_id === me;
    if (!iAmHost && m.guest_id !== me) continue;
    const other = iAmHost ? m.guest_id! : m.host_id;
    const result: MatchResult = m.winner_id === null ? "draw" : m.winner_id === me ? "win" : "loss";
    const rec = out.get(other) ?? { wins: 0, losses: 0, draws: 0, matches: [] };
    if (result === "win") rec.wins++;
    else if (result === "loss") rec.losses++;
    else rec.draws++;
    rec.matches.push({
      id: m.id,
      result,
      myHp: iAmHost ? m.host_hp : m.guest_hp,
      theirHp: iAmHost ? m.guest_hp : m.host_hp,
      abandoned: m.status === "abandoned",
      at: m.finished_at ?? m.created_at,
    });
    out.set(other, rec);
  }
  return out;
}

/** Your overall online record (every opponent together). */
export function totalRecord(h2h: Map<string, HeadToHead>): { wins: number; losses: number; draws: number } {
  let wins = 0, losses = 0, draws = 0;
  for (const r of h2h.values()) {
    wins += r.wins;
    losses += r.losses;
    draws += r.draws;
  }
  return { wins, losses, draws };
}
