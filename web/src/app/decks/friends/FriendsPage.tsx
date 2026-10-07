"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Check, Copy, Eye, Plus, Swords, Trophy, Users, X } from "@/ui/icons";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import {
  displayName,
  levelFor,
  normalizeHandle,
  rankFriends,
  xpForLevel,
  headToHead,
  totalRecord,
  type FriendRequest,
  type FriendRow,
  type HeadToHead,
  type MatchRow,
  type RankBy,
  type SendResult,
} from "../_lib/social";
import LoadingScene from "../review/battle/_components/LoadingScene";
import { formatDateMn } from "../_lib/dates";

// The web's friends page — the same 0026 RPCs as mobile's Найзууд tab: a
// handle to be found by (never email), requests, each friend's activity, and
// a friends-only leaderboard by weekly XP, total XP or ELO.

interface Me {
  handle: string | null;
  share_activity: boolean;
}

const inputCls = "rounded-control border border-line bg-surface px-3 py-2 text-sm";

const SEND_MESSAGE: Record<SendResult, string> = {
  sent: T.socialSent,
  accepted: T.socialAccepted,
  already: T.socialAlready,
  not_found: T.socialNotFound,
  self: T.socialSelf,
};

export default function FriendsPage() {
  const [me, setMe] = useState<Me | null>(null);
  const [rows, setRows] = useState<FriendRow[] | null>(null);
  const [requests, setRequests] = useState<FriendRequest[]>([]);
  const [unavailable, setUnavailable] = useState(false);
  const [tab, setTab] = useState<"friends" | "board">("friends");

  const load = useCallback(async () => {
    const { data: auth } = await supabase.auth.getUser();
    const uid = auth.user?.id;
    if (!uid) return;
    const [profile, overview, reqs] = await Promise.all([
      supabase.from("profiles").select("handle, share_activity").eq("id", uid).maybeSingle(),
      supabase.rpc("friend_overview"),
      supabase.rpc("friend_requests"),
    ]);
    // A missing column or function means 0026 isn't applied: say so plainly
    // instead of rendering an empty page that looks like "no friends".
    if (profile.error || overview.error) {
      setUnavailable(true);
      setRows([]);
      return;
    }
    setUnavailable(false);
    setMe((profile.data as Me | null) ?? { handle: null, share_activity: true });
    setRows((overview.data as FriendRow[]) ?? []);
    setRequests((reqs.data as FriendRequest[]) ?? []);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- initial fetch
    void load();
  }, [load]);

  if (rows === null) return <LoadingScene label={T.loading} />;

  return (
    <div className="mx-auto max-w-3xl px-4 py-6 sm:py-8">
      <h1 className="flex items-center gap-2 text-2xl font-bold text-ink">
        <Users size={22} className="text-seal" /> {T.socialTitle}
      </h1>

      {unavailable ? (
        <p className="mt-6 rounded-control bg-paper-dim px-4 py-3 text-sm text-ink-soft">{T.socialUnavailable}</p>
      ) : (
        <>
          <div className="mt-4 flex gap-1 rounded-control bg-paper-dim p-1 text-sm">
            {(["friends", "board"] as const).map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-control px-3 py-1.5 font-medium transition ${
                  tab === t ? "bg-surface text-ink shadow-sm" : "text-ink-soft hover:text-ink"
                }`}
              >
                {t === "friends" ? <Users size={14} /> : <Trophy size={14} />}
                {t === "friends" ? T.socialTabFriends : T.socialTabBoard}
              </button>
            ))}
          </div>

          {tab === "friends" ? (
            <FriendsTab me={me} rows={rows} requests={requests} onChange={load} />
          ) : (
            <BoardTab rows={rows} />
          )}
        </>
      )}
    </div>
  );
}

// ---- Friends -----------------------------------------------------------------

function FriendsTab({
  me,
  rows,
  requests,
  onChange,
}: {
  me: Me | null;
  rows: FriendRow[];
  requests: FriendRequest[];
  onChange: () => Promise<void>;
}) {
  const [add, setAdd] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function sendRequest() {
    if (!add.trim()) return;
    setBusy(true);
    const { data, error } = await supabase.rpc("send_friend_request", {
      p_handle: add.trim().replace(/^@/, ""),
    });
    setBusy(false);
    if (error) return setMessage(T.socialUnavailable);
    const result = data as SendResult;
    setMessage(SEND_MESSAGE[result] ?? T.socialNotFound);
    if (result === "sent" || result === "accepted") setAdd("");
    await onChange();
  }

  async function act(fn: string, args: Record<string, unknown>) {
    await supabase.rpc(fn, args);
    await onChange();
  }

  const mine = rows.filter((r) => r.is_me);
  const friends = rows
    .filter((r) => !r.is_me)
    .sort((a, b) => (b.xp_week ?? -1) - (a.xp_week ?? -1));

  return (
    <div className="mt-5 space-y-5">
      {me?.handle ? (
        <MyHandle handle={me.handle} share={me.share_activity} onChange={onChange} />
      ) : (
        <HandleCard onSaved={onChange} />
      )}

      {me?.handle && (
        <div>
          <div className="flex gap-2">
            <input
              value={add}
              onChange={(e) => setAdd(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && sendRequest()}
              placeholder={T.socialAddHint}
              aria-label={T.socialAddFriend}
              className={`${inputCls} flex-1`}
            />
            <button onClick={sendRequest} disabled={busy} className="hk-btn hk-btn-primary px-4 py-2 text-sm">
              <Plus size={15} /> {T.socialAdd}
            </button>
          </div>
          {message && <p className="mt-1.5 text-xs text-ink-soft">{message}</p>}
        </div>
      )}

      {requests.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm font-semibold text-ink">{T.socialRequests}</h2>
          <div className="space-y-2">
            {requests.map((r) => (
              <div key={r.other_id} className="hk-card flex items-center gap-3 px-4 py-3">
                <Avatar name={displayName(r)} image={r.image} />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-semibold text-ink">{displayName(r)}</p>
                  <p className="text-xs text-ink-mute">
                    @{r.handle}
                    {!r.incoming && ` · ${T.socialOutgoing}`}
                  </p>
                </div>
                {r.incoming ? (
                  <>
                    <button
                      aria-label={T.socialDecline}
                      onClick={() => act("respond_friend_request", { p_from: r.other_id, p_accept: false })}
                      className="hk-btn px-2 py-1.5"
                    >
                      <X size={15} />
                    </button>
                    <button
                      aria-label={T.socialAccept}
                      onClick={() => act("respond_friend_request", { p_from: r.other_id, p_accept: true })}
                      className="hk-btn hk-btn-primary px-2 py-1.5"
                    >
                      <Check size={15} />
                    </button>
                  </>
                ) : (
                  <button onClick={() => act("remove_friend", { p_other: r.other_id })} className="hk-btn px-3 py-1.5 text-xs">
                    {T.socialCancelRequest}
                  </button>
                )}
              </div>
            ))}
          </div>
        </section>
      )}

      <section className="space-y-3">
        {mine.map((r) => (
          <ActivityCard key={r.user_id} row={r} />
        ))}
        {friends.length === 0 ? (
          <p className="py-6 text-center text-sm text-ink-mute">{T.socialNoFriends}</p>
        ) : (
          friends.map((r) => (
            <ActivityCard
              key={r.user_id}
              row={r}
              onRemove={() => act("remove_friend", { p_other: r.user_id })}
            />
          ))
        )}
      </section>
    </div>
  );
}

function HandleCard({ onSaved }: { onSaved: () => Promise<void> }) {
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function save() {
    const handle = normalizeHandle(value);
    if (!handle) return setError(T.socialHandleFormat);
    setBusy(true);
    const { data: auth } = await supabase.auth.getUser();
    const { error: err } = await supabase
      .from("profiles")
      .update({ handle })
      .eq("id", auth.user?.id ?? "");
    setBusy(false);
    if (err) {
      // 23505 unique violation, 23514 check violation (the server's own rule).
      return setError(err.code === "23505" ? T.socialHandleTaken : err.code === "23514" ? T.socialHandleFormat : T.socialHandleFailed);
    }
    setError(null);
    await onSaved();
  }

  return (
    <div className="hk-card p-5">
      <h2 className="text-base font-bold text-ink">{T.socialPickHandle}</h2>
      <p className="mt-1 text-xs text-ink-mute">{T.socialPickHandleDesc}</p>
      <div className="mt-3 flex gap-2">
        <div className="flex flex-1 items-center rounded-control border border-line bg-surface pl-3">
          <span className="text-sm text-ink-mute">@</span>
          <input
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && save()}
            maxLength={20}
            aria-label={T.socialHandleLabel}
            className="flex-1 bg-transparent px-1 py-2 text-sm outline-none"
          />
        </div>
        <button onClick={save} disabled={busy} className="hk-btn hk-btn-primary px-4 py-2 text-sm">
          {T.socialSave}
        </button>
      </div>
      <p className={`mt-1.5 text-xs ${error ? "text-red-600" : "text-ink-mute"}`}>{error ?? T.socialHandleFormat}</p>
    </div>
  );
}

function MyHandle({ handle, share, onChange }: { handle: string; share: boolean; onChange: () => Promise<void> }) {
  const [copied, setCopied] = useState(false);

  async function toggleShare() {
    const { data: auth } = await supabase.auth.getUser();
    await supabase.from("profiles").update({ share_activity: !share }).eq("id", auth.user?.id ?? "");
    await onChange();
  }

  return (
    <div className="hk-card flex flex-wrap items-center gap-3 px-5 py-4">
      <span className="text-lg font-extrabold text-ink">@{handle}</span>
      <button
        onClick={async () => {
          await navigator.clipboard.writeText(`@${handle}`).catch(() => {});
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        }}
        className="hk-btn px-2.5 py-1 text-xs"
      >
        <Copy size={13} /> {copied ? T.socialCopied : T.socialCopyHandle}
      </button>
      <label className="ml-auto flex cursor-pointer items-center gap-2 text-xs text-ink-soft" title={T.socialShareSettingDesc}>
        <Eye size={14} />
        {T.socialShareSetting}
        <input type="checkbox" checked={share} onChange={toggleShare} className="h-4 w-4 accent-[var(--color-seal)]" />
      </label>
    </div>
  );
}

function Avatar({ name, image, size = 40 }: { name: string; image: string | null; size?: number }) {
  // Only https images: a profile picture URL comes from the identity provider,
  // and a plain-http or data: value has no business being loaded here.
  if (image?.startsWith("https://")) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={image} alt="" width={size} height={size} className="shrink-0 rounded-full" referrerPolicy="no-referrer" />;
  }
  return (
    <span
      style={{ width: size, height: size }}
      className="flex shrink-0 items-center justify-center rounded-full bg-seal-tint font-bold text-seal"
    >
      {name.charAt(0).toUpperCase()}
    </span>
  );
}

function ActivityCard({ row: r, onRemove }: { row: FriendRow; onRemove?: () => void }) {
  const xp = r.xp_total ?? 0;
  const lv = levelFor(xp);
  const from = xpForLevel(lv);
  const to = xpForLevel(lv + 1);
  const name = displayName(r);

  return (
    <div className={`hk-card px-5 py-4 ${r.is_me ? "ring-1 ring-seal" : ""}`}>
      <div className="flex items-center gap-3">
        <Avatar name={name} image={r.image} size={44} />
        <div className="min-w-0 flex-1">
          <p className="truncate font-bold text-ink">
            {name}
            {r.is_me && <span className="font-normal text-ink-mute"> ({T.socialYou})</span>}
          </p>
          <p className="text-xs text-ink-mute">
            {[r.handle && `@${r.handle}`, r.shares && T.socialLevel(lv), r.shares && r.elo !== null && T.socialElo(r.elo)]
              .filter(Boolean)
              .join(" · ")}
          </p>
        </div>
        {!r.is_me && r.shares && (
          <Link href="/decks/review/duel" className="hk-btn px-2.5 py-1 text-xs" title={T.socialChallenge}>
            <Swords size={13} />
          </Link>
        )}
        {onRemove && (
          <button
            onClick={() => window.confirm(`${T.socialRemove}?`) && onRemove()}
            className="hk-btn px-2 py-1 text-xs"
            aria-label={T.socialRemove}
          >
            <X size={13} />
          </button>
        )}
      </div>

      {!r.shares ? (
        <p className="mt-2 text-xs text-ink-mute">{T.socialHidden}</p>
      ) : (
        <>
          <div className="mt-3 flex items-center gap-2">
            <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-line-soft">
              <div className="h-full bg-seal" style={{ width: `${to === from ? 100 : ((xp - from) / (to - from)) * 100}%` }} />
            </div>
            <span className="text-xs font-semibold text-ink">{T.socialXp(xp)}</span>
          </div>
          <p className="mt-3 text-xs text-ink-mute">{T.socialToday}</p>
          <div className="mt-1 flex flex-wrap gap-1.5 text-xs">
            {[
              T.socialAddedToday(r.added_today ?? 0),
              T.socialReviewedToday(r.reviewed_today ?? 0),
              T.socialWordsLearned(r.words_learned ?? 0),
              T.socialKanjiLearned(r.kanji_learned ?? 0),
            ].map((t) => (
              <span key={t} className="rounded-full border border-line-soft px-2.5 py-1 text-ink-soft">
                {t}
              </span>
            ))}
          </div>
          {r.recent_kanji && r.recent_kanji.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1">
              {r.recent_kanji.map((k) => (
                <span key={k} className="rounded-control bg-seal-tint px-2 py-0.5 text-lg font-bold text-ink">
                  {k}
                </span>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}

// ---- Leaderboard (friends only) -------------------------------------------

/** One person on the board. */
interface Entry {
  userId: string;
  rank: number;
  name: string;
  sub: string;
  image: string | null;
  value: number;
  isMe: boolean;
}

function BoardTab({ rows }: { rows: FriendRow[] }) {
  const [by, setBy] = useState<RankBy>("week");
  const [open, setOpen] = useState<string | null>(null);
  const [h2h, setH2h] = useState<Map<string, HeadToHead> | null>(null);
  const label: Record<RankBy, string> = { week: T.socialBoardWeek, total: T.socialBoardTotal, elo: T.socialBoardElo };
  const meId = rows.find((r) => r.is_me)?.user_id ?? null;

  // Your own duels (RLS: matches you played), tallied per opponent.
  useEffect(() => {
    if (!meId) return;
    let cancelled = false;
    supabase
      .from("matches")
      .select("id, host_id, guest_id, host_hp, guest_hp, winner_id, status, finished_at, created_at")
      .in("status", ["finished", "abandoned"])
      .order("created_at", { ascending: false })
      .limit(300)
      .then(({ data }) => {
        if (!cancelled) setH2h(headToHead((data as MatchRow[]) ?? [], meId));
      });
    return () => {
      cancelled = true;
    };
  }, [meId]);

  const entries: Entry[] = rankFriends(rows, by).map((r, i) => ({
    userId: r.user_id,
    rank: i + 1,
    name: displayName(r),
    sub: [r.handle && `@${r.handle}`, T.socialLevel(levelFor(r.xp_total ?? 0))].filter(Boolean).join(" · "),
    image: r.image,
    value: by === "elo" ? (r.elo ?? 1000) : by === "week" ? (r.xp_week ?? 0) : (r.xp_total ?? 0),
    isMe: r.is_me,
  }));

  return (
    <div className="mt-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-ink-soft">{T.socialBoardFriendsOnly}</p>
        <Switch value={by} onChange={(v) => setBy(v as RankBy)} options={(Object.keys(label) as RankBy[]).map((k) => ({ value: k, label: label[k] }))} />
      </div>
      <p className="mt-2 text-xs text-ink-mute">{by === "elo" ? T.socialBoardEloNote : T.socialXpNote}</p>

      {entries.length < 2 ? (
        <p className="py-10 text-center text-sm text-ink-mute">{T.socialBoardEmpty}</p>
      ) : (
        <Board entries={entries} by={by} h2h={h2h} open={open} onToggle={(id) => setOpen((o) => (o === id ? null : id))} />
      )}
    </div>
  );
}

const PODIUM = [
  { ring: "ring-[#d4a63a]", bg: "bg-[#f6ead0]", text: "text-[#8a6416]", h: "h-20" },
  { ring: "ring-[#a9b1bb]", bg: "bg-[#eceff2]", text: "text-[#4c5560]", h: "h-14" },
  { ring: "ring-[#c48a5a]", bg: "bg-[#f4e4d6]", text: "text-[#7a4a24]", h: "h-10" },
];

function formatValue(v: number, by: RankBy) {
  return by === "elo" ? String(v) : T.socialXp(v);
}

/** "3–2" (and "–1" draw) from your side; null when you've never played. */
function recordText(r: { wins: number; losses: number; draws: number } | undefined) {
  if (!r || r.wins + r.losses + r.draws === 0) return null;
  return `${r.wins}–${r.losses}${r.draws ? ` · ${T.socialDraws(r.draws)}` : ""}`;
}

/** The top three on a podium (2 · 1 · 3), everyone else as rows; tap anyone for your duels with them. */
function Board({
  entries,
  by,
  h2h,
  open,
  onToggle,
}: {
  entries: Entry[];
  by: RankBy;
  h2h: Map<string, HeadToHead> | null;
  open: string | null;
  onToggle: (userId: string) => void;
}) {
  const top = entries.slice(0, 3);
  const rest = entries.slice(3);
  const leader = Math.max(1, ...entries.map((e) => e.value));
  const order = [top[1], top[0], top[2]].filter(Boolean) as Entry[];
  const mine = h2h ? totalRecord(h2h) : null;
  const vsText = (e: Entry) => (e.isMe ? recordText(mine ?? undefined) : recordText(h2h?.get(e.userId)));
  const openEntry = entries.find((e) => e.userId === open) ?? null;

  return (
    <div className="mt-4">
      <div className="hk-card flex items-end justify-center gap-2 overflow-hidden px-3 pt-6 sm:gap-4 sm:px-6">
        {order.map((e) => {
          const p = PODIUM[e.rank - 1];
          const vs = vsText(e);
          return (
            <button
              key={e.userId}
              type="button"
              onClick={() => onToggle(e.userId)}
              aria-expanded={open === e.userId}
              className="group flex w-1/3 max-w-[180px] flex-col items-center text-center"
            >
              <div className={`rounded-full ring-4 ${p.ring} ${e.isMe ? "outline outline-2 outline-offset-4 outline-seal" : ""}`}>
                <Avatar name={e.name} image={e.image} size={e.rank === 1 ? 64 : 52} />
              </div>
              <p className="mt-3 w-full truncate text-sm font-semibold text-ink group-hover:underline">
                {e.name}
                {e.isMe && <span className="font-normal text-ink-mute"> ({T.socialYou})</span>}
              </p>
              <p className={`text-sm font-extrabold tabular-nums ${p.text}`}>{formatValue(e.value, by)}</p>
              <p className="h-4 w-full truncate text-[11px] text-ink-mute">{vs && (e.isMe ? T.socialMyRecord(vs) : T.socialVsYou(vs))}</p>
              <div
                className={`mt-2 flex w-full items-start justify-center rounded-t-control pt-1.5 text-2xl font-extrabold ${p.bg} ${p.text} ${p.h} ${
                  open === e.userId ? "ring-2 ring-inset ring-seal/40" : ""
                }`}
              >
                {e.rank}
              </div>
            </button>
          );
        })}
      </div>

      {openEntry && top.includes(openEntry) && <DuelLog entry={openEntry} h2h={h2h} mine={mine} />}

      {rest.length > 0 && (
        <ol className="hk-card mt-3 overflow-hidden py-1">
          {rest.map((e) => {
            const vs = vsText(e);
            return (
              <li key={e.userId}>
                <button
                  type="button"
                  onClick={() => onToggle(e.userId)}
                  aria-expanded={open === e.userId}
                  className={`relative flex w-full items-center gap-3 px-4 py-2.5 text-left ${e.isMe ? "bg-seal-tint" : "hover:bg-paper"}`}
                >
                  {e.isMe && <span className="absolute inset-y-1.5 left-0 w-[3px] rounded-r bg-seal" />}
                  <span className="w-7 shrink-0 text-center text-sm font-bold tabular-nums text-ink-mute">{e.rank}</span>
                  <Avatar name={e.name} image={e.image} size={32} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-ink">
                      {e.name}
                      {e.isMe && <span className="font-normal text-ink-mute"> ({T.socialYou})</span>}
                    </p>
                    <div className="mt-1 flex items-center gap-2">
                      <span className="h-1 flex-1 overflow-hidden rounded-full bg-paper-dim">
                        <span className="block h-full rounded-full bg-seal/70" style={{ width: `${Math.max(2, (e.value / leader) * 100)}%` }} />
                      </span>
                      <span className="shrink-0 text-[11px] text-ink-mute">
                        {vs ? (e.isMe ? T.socialMyRecord(vs) : T.socialVsYou(vs)) : e.sub}
                      </span>
                    </div>
                  </div>
                  <span className="w-20 shrink-0 text-right text-sm font-extrabold tabular-nums text-ink">{formatValue(e.value, by)}</span>
                </button>
                {open === e.userId && <DuelLog entry={e} h2h={h2h} mine={mine} inline />}
              </li>
            );
          })}
        </ol>
      )}
    </div>
  );
}

/** Your online duels with one friend (or, on your own row, your overall record). */
function DuelLog({
  entry,
  h2h,
  mine,
  inline = false,
}: {
  entry: Entry;
  h2h: Map<string, HeadToHead> | null;
  mine: { wins: number; losses: number; draws: number } | null;
  inline?: boolean;
}) {
  const rec = entry.isMe ? null : (h2h?.get(entry.userId) ?? null);
  const box = inline ? "border-t border-line-soft bg-paper/60 px-4 py-3" : "hk-card mt-3 px-4 py-3";

  if (!h2h) return <div className={`${box} text-sm text-ink-mute`}>{T.loading}</div>;

  if (entry.isMe) {
    return (
      <div className={box}>
        <p className="text-sm font-semibold text-ink">{T.socialMyDuels}</p>
        <RecordStrip wins={mine?.wins ?? 0} losses={mine?.losses ?? 0} draws={mine?.draws ?? 0} />
      </div>
    );
  }

  return (
    <div className={box}>
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-semibold text-ink">{T.socialDuelsWith(entry.name)}</p>
        <Link href="/decks/review/duel" className="flex items-center gap-1 text-xs font-semibold text-seal hover:underline">
          <Swords size={13} /> {T.socialChallenge}
        </Link>
      </div>
      {!rec ? (
        <p className="mt-2 text-sm text-ink-mute">{T.socialNoDuels}</p>
      ) : (
        <>
          <RecordStrip wins={rec.wins} losses={rec.losses} draws={rec.draws} />
          <ul className="mt-3 space-y-1">
            {rec.matches.slice(0, 8).map((m) => (
              <li key={m.id} className="flex items-center gap-3 text-sm">
                <span
                  className={`w-16 shrink-0 rounded-full px-2 py-0.5 text-center text-xs font-bold ${
                    m.result === "win"
                      ? "bg-emerald-100 text-emerald-800"
                      : m.result === "loss"
                        ? "bg-red-100 text-red-800"
                        : "bg-paper-dim text-ink-soft"
                  }`}
                >
                  {m.result === "win" ? T.socialWin : m.result === "loss" ? T.socialLoss : T.socialDraw}
                </span>
                <span className="shrink-0 whitespace-nowrap font-semibold tabular-nums text-ink">
                  {m.myHp} : {m.theirHp} <span className="font-normal text-ink-mute">HP</span>
                </span>
                <span className="min-w-0 flex-1 truncate text-xs text-ink-mute">{m.abandoned && T.socialLeftEarly}</span>
                <span className="shrink-0 whitespace-nowrap text-xs text-ink-mute">{formatDateMn(new Date(m.at))}</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}

function RecordStrip({ wins, losses, draws }: { wins: number; losses: number; draws: number }) {
  const total = wins + losses + draws;
  return (
    <div className="mt-2">
      <div className="flex gap-4 text-sm">
        <span>
          <b className="text-emerald-700">{wins}</b> {T.socialWins}
        </span>
        <span>
          <b className="text-red-700">{losses}</b> {T.socialLosses}
        </span>
        {draws > 0 && (
          <span>
            <b className="text-ink-soft">{draws}</b> {T.socialDrawsWord}
          </span>
        )}
      </div>
      {total > 0 && (
        <div className="mt-1.5 flex h-1.5 overflow-hidden rounded-full bg-paper-dim">
          <span className="bg-emerald-500" style={{ width: `${(wins / total) * 100}%` }} />
          <span className="bg-paper-deep" style={{ width: `${(draws / total) * 100}%` }} />
          <span className="bg-red-500" style={{ width: `${(losses / total) * 100}%` }} />
        </div>
      )}
    </div>
  );
}

/** A compact segmented switch (scope / metric). */
function Switch({
  value,
  onChange,
  options,
}: {
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string; icon?: React.ReactNode }[];
}) {
  return (
    <div role="radiogroup" className="inline-flex rounded-control bg-paper-dim p-1 text-sm">
      {options.map((o) => (
        <button
          key={o.value}
          role="radio"
          aria-checked={value === o.value}
          onClick={() => onChange(o.value)}
          className={`flex items-center gap-1.5 whitespace-nowrap rounded-control px-3 py-1 font-medium transition ${
            value === o.value ? "bg-surface text-ink shadow-sm" : "text-ink-soft hover:text-ink"
          }`}
        >
          {o.icon}
          {o.label}
        </button>
      ))}
    </div>
  );
}
