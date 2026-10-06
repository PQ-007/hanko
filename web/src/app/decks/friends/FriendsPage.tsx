"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Check, Copy, Eye, Globe, Plus, Swords, Trophy, Users, X } from "lucide-react";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import {
  displayName,
  levelFor,
  normalizeHandle,
  rankFriends,
  xpForLevel,
  type FriendRequest,
  type GlobalRow,
  type FriendRow,
  type RankBy,
  type SendResult,
} from "../_lib/social";
import LoadingScene from "../review/battle/_components/LoadingScene";

// The web's friends page — the same 0026 RPCs as mobile's Найзууд tab: a
// handle to be found by (never email), requests, each friend's activity, and
// a friends-only leaderboard by weekly XP, total XP or ELO.

interface Me {
  handle: string | null;
  share_activity: boolean;
}

const inputCls = "rounded-control border border-line bg-white px-3 py-2 text-sm";

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
                  tab === t ? "bg-white text-ink shadow-sm" : "text-ink-soft hover:text-ink"
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
            <BoardTab rows={rows} hasHandle={!!me?.handle} />
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
        <div className="flex flex-1 items-center rounded-control border border-line bg-white pl-3">
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

// ---- Leaderboard --------------------------------------------------------------

function BoardTab({ rows, hasHandle }: { rows: FriendRow[]; hasHandle: boolean }) {
  const [by, setBy] = useState<RankBy>("week");
  const [all, setAll] = useState(false);
  const ranked = rankFriends(rows, by);
  const label: Record<RankBy, string> = { week: T.socialBoardWeek, total: T.socialBoardTotal, elo: T.socialBoardElo };

  return (
    <div className="mt-5">
      <div className="mb-2 flex gap-1 rounded-control bg-paper-dim p-1 text-sm">
        {[false, true].map((a) => (
          <button
            key={String(a)}
            onClick={() => setAll(a)}
            className={`flex flex-1 items-center justify-center gap-1.5 rounded-control px-3 py-1 font-medium transition ${
              all === a ? "bg-white text-ink shadow-sm" : "text-ink-soft hover:text-ink"
            }`}
          >
            {a ? <Globe size={14} /> : <Users size={14} />}
            {a ? T.socialScopeAll : T.socialScopeFriends}
          </button>
        ))}
      </div>
      <div className="flex gap-1 text-sm">
        {(Object.keys(label) as RankBy[]).map((k) => (
          <button
            key={k}
            onClick={() => setBy(k)}
            className={`rounded-full px-3 py-1 font-medium transition ${
              by === k ? "bg-seal text-white" : "bg-paper-dim text-ink-soft hover:text-ink"
            }`}
          >
            {label[k]}
          </button>
        ))}
      </div>
      <p className="mt-2 text-xs text-ink-mute">
        {all ? T.socialGlobalNote : by === "elo" ? T.socialBoardEloNote : T.socialXpNote}
      </p>

      {all ? (
        <GlobalBoard by={by} hasHandle={hasHandle} />
      ) : ranked.length < 2 ? (
        <p className="py-10 text-center text-sm text-ink-mute">{T.socialBoardEmpty}</p>
      ) : (
        <ol className="mt-3 space-y-2">
          {ranked.map((r, i) => (
            <li key={r.user_id} className={`hk-card flex items-center gap-3 px-4 py-3 ${r.is_me ? "bg-seal-tint" : ""}`}>
              <span className="w-8 text-center text-lg font-extrabold">{i < 3 ? ["🥇", "🥈", "🥉"][i] : i + 1}</span>
              <Avatar name={displayName(r)} image={r.image} size={34} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold text-ink">
                  {displayName(r)}
                  {r.is_me && <span className="font-normal text-ink-mute"> ({T.socialYou})</span>}
                </p>
                <p className="text-xs text-ink-mute">
                  {[r.handle && `@${r.handle}`, T.socialLevel(levelFor(r.xp_total ?? 0))].filter(Boolean).join(" · ")}
                </p>
              </div>
              <span className="text-base font-extrabold text-ink">
                {by === "elo" ? (r.elo ?? 1000) : T.socialXp(by === "week" ? (r.xp_week ?? 0) : (r.xp_total ?? 0))}
              </span>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

/** The everyone board: handle and score only; your own row always shows,
 *  with its real rank, even below the top 50. */
function GlobalBoard({ by, hasHandle }: { by: RankBy; hasHandle: boolean }) {
  const [rows, setRows] = useState<GlobalRow[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    supabase.rpc("global_leaderboard", { p_by: by, p_limit: 50 }).then(({ data, error }) => {
      if (cancelled) return;
      setFailed(!!error);
      setRows((data as GlobalRow[]) ?? []);
    });
    return () => {
      cancelled = true;
    };
  }, [by]);

  if (failed) return <p className="mt-4 text-sm text-ink-mute">{T.socialUnavailable}</p>;
  if (!rows) return <p className="mt-6 text-center text-sm text-ink-mute">{T.loading}</p>;

  return (
    <div className="mt-3">
      {!hasHandle && <p className="mb-2 text-xs text-ink-soft">{T.socialGlobalNeedHandle}</p>}
      <ol className="space-y-2">
        {rows.map((r, i) => (
          <li key={r.handle}>
            {r.is_me && i > 0 && r.rank > rows[i - 1].rank + 1 && (
              <p className="py-1 text-center text-ink-mute">⋯</p>
            )}
            <div className={`hk-card flex items-center gap-3 px-4 py-3 ${r.is_me ? "bg-seal-tint" : ""}`}>
              <span className="w-8 text-center text-lg font-extrabold">
                {r.rank <= 3 ? ["🥇", "🥈", "🥉"][r.rank - 1] : r.rank}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold text-ink">
                  @{r.handle}
                  {r.is_me && <span className="font-normal text-ink-mute"> ({T.socialYou})</span>}
                  {r.is_friend && <span className="ml-1 text-xs font-normal text-ink-mute">· {T.socialFriendTag}</span>}
                </p>
                <p className="text-xs text-ink-mute">{T.socialLevel(levelFor(r.xp_total))}</p>
              </div>
              <span className="text-base font-extrabold text-ink">
                {by === "elo" ? r.elo : T.socialXp(by === "week" ? r.xp_week : r.xp_total)}
              </span>
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}
