"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { ArrowLeft, Bot, Copy, Loader2, LogIn, Swords, Users, Versus } from "@/ui/icons";
import { supabase } from "../../../_lib/db";
import { T } from "../../../_lib/strings";
import { MIN_WORDS_FOR_BATTLE } from "../../battle/_lib/quiz";
import { pickMonster } from "../../battle/_lib/monsters";
import { CHARACTER_NAMES } from "../../battle/_lib/sprites";
import { readPlayerCharacter, usePlayerCharacter } from "../../battle/_lib/playerCharacter";
import FighterSprite from "../../battle/_components/FighterSprite";
import LoadingScene from "../../battle/_components/LoadingScene";
import { BOT_DIFFICULTIES, BOT_PROFILES, type BotDifficulty } from "../_lib/bot";
import { createBotOpponent } from "../_lib/opponent";
import { createRemoteOpponent, type RemoteMatch } from "../_lib/remoteOpponent";
import { opponentLabel, type DuelInvite, type DuelOpponentInfo, type MatchRow } from "../_lib/match";
import { loadRecord } from "../_lib/record";
import { parseQuestions } from "../_lib/sharedQuestions";
import type { HeadToHead } from "../../../_lib/social";
import DuelArena, { type OnlineMatch } from "./DuelArena";

interface FriendLite {
  user_id: string;
  handle: string | null;
  name: string | null;
  image: string | null;
}

const BOT_LABEL: Record<BotDifficulty, { name: string; desc: string }> = {
  rookie: { name: T.duelBotRookie, desc: T.duelBotRookieDesc },
  rival: { name: T.duelBotRival, desc: T.duelBotRivalDesc },
  master: { name: T.duelBotMaster, desc: T.duelBotMasterDesc },
};

export default function DuelLobby() {
  const hero = usePlayerCharacter();
  const [wordCount, setWordCount] = useState<number | null>(null);
  const [userId, setUserId] = useState<string | null>(null);

  // A bot match needs nothing but a profile, so it is pure local state — no
  // row, no code, no round trip. That is the whole reason PVP.md ships it
  // first: everything below the divider is optional to having a playable mode.
  const [bot, setBot] = useState<{ difficulty: BotDifficulty; slug: string; nonce: number } | null>(
    null
  );

  const [match, setMatch] = useState<MatchRow | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Friends: who I can challenge, and challenges waiting for me (0030).
  const router = useRouter();
  const params = useSearchParams();
  const [friends, setFriends] = useState<FriendLite[]>([]);
  const [invites, setInvites] = useState<DuelInvite[]>([]);
  // Who the open invitation (the waiting room) is to.
  const [invitee, setInvitee] = useState<string | null>(null);
  // Who I'm fighting and my record with them, loaded before the intro.
  const [info, setInfo] = useState<{ matchId: string; opp: DuelOpponentInfo | null; record: HeadToHead | null } | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [wordsRes, userRes] = await Promise.all([
        supabase.from("words").select("id", { count: "exact", head: true }).eq("deleted", false),
        supabase.auth.getUser(),
      ]);
      if (cancelled) return;
      setWordCount(wordsRes.count ?? 0);
      setUserId(userRes.data.user?.id ?? null);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const refreshInvites = useCallback(async () => {
    const { data } = await supabase.rpc("duel_invites");
    setInvites((data as DuelInvite[] | null) ?? []);
  }, []);

  useEffect(() => {
    supabase.rpc("my_friends").then(({ data }) => setFriends((data as FriendLite[] | null) ?? []));
  }, []);

  // Challenges arrive while the lobby is open: a slow poll is the guarantee,
  // the global toast (DuelInviteToast) is what makes them quick elsewhere.
  useEffect(() => {
    if (match || bot) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- initial read
    void refreshInvites();
    const id = setInterval(refreshInvites, 5000);
    return () => clearInterval(id);
  }, [match, bot, refreshInvites]);

  async function inviteFriend(friendId: string, name: string) {
    setBusy(true);
    setError(null);
    const { data, error: err } = await supabase.rpc("invite_to_duel", { p_friend: friendId, p_character: hero });
    setBusy(false);
    if (err || !data) return setError(T.duelInviteFailed);
    setInvitee(name);
    setMatch(data as MatchRow);
  }

  async function acceptInvite(matchId: string) {
    setBusy(true);
    setError(null);
    const { data, error: err } = await supabase.rpc("accept_duel_invite", { p_match_id: matchId, p_character: hero });
    setBusy(false);
    if (err || !data) {
      void refreshInvites();
      return setError(T.duelInviteAcceptFailed);
    }
    setMatch(data as MatchRow);
  }

  async function declineInvite(matchId: string) {
    await supabase.rpc("decline_duel_invite", { p_match_id: matchId });
    void refreshInvites();
  }

  // Links from elsewhere: ?invite=<friend id> (the friends page's challenge
  // button) and ?accept=<match id> (the invitation toast). Each is used once.
  const handled = useRef(false);
  useEffect(() => {
    if (handled.current || wordCount === null || wordCount < MIN_WORDS_FOR_BATTLE) return;
    const invite = params.get("invite");
    const accept = params.get("accept");
    if (!invite && !accept) return;
    handled.current = true;
    router.replace("/decks/review/duel");
    // eslint-disable-next-line react-hooks/set-state-in-effect -- one-time deep link
    if (invite) void inviteFriend(invite, params.get("name") ?? "");
    else if (accept) void acceptInvite(accept);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wordCount, params]);

  // The moment a match goes live: who is across the table, and our record.
  useEffect(() => {
    if (!match || match.status !== "active" || !userId) return;
    if (info?.matchId === match.id) return;
    const opponentId = match.host_id === userId ? match.guest_id : match.host_id;
    if (!opponentId) return;
    let cancelled = false;
    (async () => {
      const [opp, record] = await Promise.all([
        supabase.rpc("duel_opponent", { p_match_id: match.id }),
        loadRecord(userId, opponentId),
      ]);
      if (cancelled) return;
      const row = ((opp.data as DuelOpponentInfo[] | null) ?? [])[0] ?? null;
      setInfo({ matchId: match.id, opp: row, record });
    })();
    return () => {
      cancelled = true;
    };
  }, [match, userId, info?.matchId]);

  // Waiting room. The host sits on their own match row until someone joins;
  // Realtime tells them, and a slow poll covers the case where the channel
  // never connected — the host would otherwise wait forever on a game that
  // had already started.
  useEffect(() => {
    if (!match || match.status !== "lobby") return;
    let cancelled = false;

    const refresh = async () => {
      const { data } = await supabase.from("matches").select("*").eq("id", match.id).maybeSingle();
      if (!cancelled && data) setMatch(data as MatchRow);
    };

    const channel = supabase
      .channel(`lobby:${match.id}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${match.id}` },
        () => refresh()
      )
      .subscribe();
    const poll = setInterval(refresh, 3000);

    return () => {
      cancelled = true;
      clearInterval(poll);
      supabase.removeChannel(channel);
    };
  }, [match]);

  const startBot = useCallback((difficulty: BotDifficulty) => {
    setBot({ difficulty, slug: pickMonster(readPlayerCharacter()), nonce: Date.now() });
  }, []);

  async function createMatch() {
    setBusy(true);
    setError(null);
    const { data, error: err } = await supabase.rpc("create_match", { p_character: hero });
    setBusy(false);
    if (err || !data) return setError(T.duelCreateFailed);
    setMatch(data as MatchRow);
  }

  async function joinMatch() {
    const trimmed = code.trim().toUpperCase();
    if (!trimmed) return;
    setBusy(true);
    setError(null);
    const { data, error: err } = await supabase.rpc("join_match", {
      p_code: trimmed,
      p_character: hero,
    });
    setBusy(false);
    if (err || !data) return setError(T.duelJoinFailed);
    setMatch(data as MatchRow);
  }

  async function cancelMatch() {
    if (!match) return;
    // concede, not forfeit: if a guest joined in the same instant, they win.
    // forfeit_match would hand the win to whoever calls it. Without 0026 the
    // fallback is only reached for a lobby, which has no winner anyway.
    const { error: err } = await supabase.rpc("concede_match", { p_match_id: match.id });
    if (err) await supabase.rpc("forfeit_match", { p_match_id: match.id });
    setMatch(null);
  }

  const botOpponent = useMemo(() => {
    if (!bot) return null;
    return createBotOpponent(
      BOT_LABEL[bot.difficulty].name,
      bot.slug,
      BOT_PROFILES[bot.difficulty]
    );
    // `nonce` is what makes a rematch a genuinely new driver rather than the
    // finished one handed back.
  }, [bot]);

  const remoteOpponent = useMemo(() => {
    if (!match || match.status !== "active" || !userId || info?.matchId !== match.id) return null;
    const isHost = match.host_id === userId;
    const opponentId = isHost ? match.guest_id : match.host_id;
    if (!opponentId) return null;
    const spec: RemoteMatch = {
      matchId: match.id,
      opponentId,
      name: opponentLabel(info.opp, T.multiplayerTitle),
      slug: (isHost ? match.guest_character : match.host_character) ?? "knight",
      baselineMs: (isHost ? match.guest_baseline_ms : match.host_baseline_ms) ?? null,
    };
    return createRemoteOpponent(spec);
  }, [match, userId, info]);

  const online = useMemo<OnlineMatch | null>(() => {
    if (!match || !userId || !info || info.matchId !== match.id) return null;
    const opponentId = match.host_id === userId ? match.guest_id : match.host_id;
    if (!opponentId) return null;
    const handle = info.opp?.name && info.opp.handle ? `@${info.opp.handle}` : null;
    const foeSub = [handle, info.opp ? `${info.opp.elo} ELO` : null].filter(Boolean).join(" · ") || null;
    return {
      matchId: match.id,
      meId: userId,
      opponentId,
      foeSub,
      record: info.record,
      questions: parseQuestions(match.questions),
      // A rematch is a new match row: swap it in and the arena (keyed by id)
      // starts fresh.
      onRematchStarted: (m) => {
        setInfo(null);
        setMatch(m);
      },
    };
  }, [match, userId, info]);

  if (wordCount === null) return <LoadingScene label={T.duelLoading} />;

  if (wordCount < MIN_WORDS_FOR_BATTLE) {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center">
        <p className="text-sm text-ink-soft">{T.notEnoughWordsBattle}</p>
        <Link href="/decks" className="mt-5 hk-btn hk-btn-primary px-5 py-2.5 text-sm">
          {T.decksNav}
        </Link>
      </div>
    );
  }

  if (botOpponent && bot) {
    return (
      <DuelArena
        key={bot.nonce}
        opponent={botOpponent}
        onRematch={() => startBot(bot.difficulty)}
      />
    );
  }

  if (remoteOpponent && match && online) {
    return (
      <DuelArena
        key={match.id}
        opponent={remoteOpponent}
        roundCount={match.round_count}
        online={online}
      />
    );
  }

  // Active, but still finding out who the opponent is (a moment).
  if (match && match.status === "active") return <LoadingScene label={T.duelLoading} />;

  // Host waiting room.
  if (match && match.status === "lobby") {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center">
        <Loader2 size={24} className="mx-auto animate-spin text-ink-mute" />
        {match.invited_id ? (
          <>
            <h1 className="mt-5 text-xl font-bold text-ink">
              {invitee ? T.duelInviteSentTo(invitee) : T.duelWaitingGuest}
            </h1>
            <p className="mt-1 text-sm text-ink-soft">{T.duelInviteSentDesc}</p>
          </>
        ) : (
          <>
            <h1 className="mt-5 text-xl font-bold text-ink">{T.duelWaitingGuest}</h1>
            <p className="mt-1 text-sm text-ink-soft">{T.duelCodeShare}</p>
            <button
              onClick={() => navigator.clipboard?.writeText(match.join_code ?? "")}
              className="mt-6 flex w-full items-center justify-center gap-3 rounded-card border border-line bg-surface py-6 text-4xl font-extrabold tracking-[0.3em] text-ink transition hover:bg-paper-dim"
            >
              {match.join_code}
              <Copy size={18} className="text-ink-mute" />
            </button>
          </>
        )}
        <button onClick={cancelMatch} className="mt-6 hk-btn hk-btn-quiet px-5 py-2.5 text-sm">
          {T.duelCancel}
        </button>
      </div>
    );
  }

  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-8 sm:py-12">
      <header className="flex flex-col items-center gap-2 text-center">
        <span className="rounded-full bg-seal-tint px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-seal">
          {T.duelKicker}
        </span>
        <h1 className="text-3xl font-extrabold tracking-tight text-ink">{T.duelLobbyTitle}</h1>
        <p className="text-xs text-ink-mute">{T.duelNotScheduled}</p>
      </header>

      {error && (
        <p className="mt-6 rounded-control border border-line bg-paper-dim px-4 py-2.5 text-center text-sm text-ink">
          {error}
        </p>
      )}

      {invites.length > 0 && (
        <section className="mt-6" aria-label={T.duelInvitesTitle}>
          <h2 className="text-sm font-semibold text-ink">{T.duelInvitesTitle}</h2>
          <ul className="mt-2 flex flex-col gap-2">
            {invites.map((inv) => {
              const who = opponentLabel({ name: inv.host_name, handle: inv.host_handle }, T.multiplayerTitle);
              return (
                <li
                  key={inv.match_id}
                  className="flex flex-wrap items-center gap-3 rounded-card border border-seal bg-seal-tint px-4 py-3"
                >
                  <Swords size={18} className="shrink-0 text-seal" />
                  <span className="min-w-0 flex-1 text-sm font-semibold text-ink">
                    {inv.rematch ? T.duelRematchFrom(who) : T.duelInviteFrom(who)}
                  </span>
                  <button
                    onClick={() => acceptInvite(inv.match_id)}
                    disabled={busy}
                    className="hk-btn hk-btn-primary px-4 py-2 text-sm disabled:opacity-60"
                  >
                    {T.duelInviteAccept}
                  </button>
                  <button onClick={() => declineInvite(inv.match_id)} className="hk-btn hk-btn-quiet px-3 py-2 text-sm">
                    {T.duelInviteDecline}
                  </button>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      <section className="mt-7">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-ink">
          <Bot size={16} className="text-seal" /> {T.duelBotSection}
        </h2>
        <p className="mt-0.5 text-xs text-ink-mute">{T.duelBotDesc}</p>
        {/* Phones: three compact tiles in a row (name + start); the one-line
            description joins them from sm up. */}
        <div className="mt-3 grid grid-cols-3 gap-2">
          {BOT_DIFFICULTIES.map((d) => (
            <button
              key={d}
              onClick={() => startBot(d)}
              title={BOT_LABEL[d].desc}
              className="hk-card hk-card-interactive group flex flex-col items-center gap-1 px-2 py-3 text-center sm:gap-2 sm:px-4 sm:py-5"
            >
              <span className="text-[13px] font-semibold text-ink sm:text-sm">{BOT_LABEL[d].name}</span>
              <span className="hidden text-xs leading-relaxed text-ink-mute sm:block">{BOT_LABEL[d].desc}</span>
              <span className="flex items-center gap-1 text-[11px] font-medium text-seal sm:mt-1">
                <Versus size={12} /> {T.practiceStart}
              </span>
            </button>
          ))}
        </div>
      </section>

      <section className="mt-8">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-ink">
          <Users size={16} className="text-seal" /> {T.duelFriendSection}
        </h2>
        <p className="mt-0.5 text-xs text-ink-mute">{T.multiplayerDesc}</p>

        {/* Friends first: one tap, no code. */}
        <p className="mt-3 text-xs font-semibold text-ink-soft">{T.duelInviteFriendSection}</p>
        {friends.length === 0 ? (
          <p className="mt-1 text-xs text-ink-mute">
            {T.duelNoFriends}{" "}
            <Link href="/decks/friends" className="font-medium text-seal hover:underline">
              {T.friendsNav}
            </Link>
          </p>
        ) : (
          <ul className="mt-2 max-h-60 divide-y divide-line-soft overflow-y-auto rounded-card border border-line-soft bg-surface">
            {friends.map((f) => {
              const label = opponentLabel(f, "—");
              return (
                <li key={f.user_id} className="flex items-center gap-3 px-3 py-2.5">
                  <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-seal-tint text-sm font-bold text-seal">
                    {label.replace("@", "").charAt(0).toUpperCase()}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-semibold text-ink">{label}</span>
                    {f.name && f.handle && <span className="block truncate text-xs text-ink-mute">@{f.handle}</span>}
                  </span>
                  <button
                    onClick={() => inviteFriend(f.user_id, label)}
                    disabled={busy}
                    className="hk-btn hk-btn-primary px-3 py-1.5 text-xs disabled:opacity-60"
                  >
                    <Swords size={13} /> {T.duelInviteBtn}
                  </button>
                </li>
              );
            })}
          </ul>
        )}

        <div className="mt-4 flex flex-col gap-2 sm:flex-row">
          <button
            onClick={createMatch}
            disabled={busy}
            className="hk-btn hk-btn-primary flex-1 px-4 py-3 text-sm disabled:opacity-60"
          >
            {busy ? <Loader2 size={15} className="animate-spin" /> : <Swords size={15} />}
            {T.duelCreate}
          </button>
        </div>

        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
          <input
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            onKeyDown={(e) => e.key === "Enter" && joinMatch()}
            placeholder={T.duelCodePlaceholder}
            aria-label={T.duelCodeLabel}
            maxLength={4}
            className="flex-1 rounded-control border border-line bg-surface px-4 py-3 text-center text-lg font-bold tracking-[0.3em] uppercase focus:border-seal focus:outline-none hk-input focus:ring-2 focus:ring-seal-tint"
          />
          <button
            onClick={joinMatch}
            disabled={busy || code.trim().length === 0}
            className="hk-btn hk-btn-quiet px-5 py-3 text-sm disabled:opacity-50"
          >
            <LogIn size={15} /> {T.duelJoin}
          </button>
        </div>
      </section>

      {/* Whoever you walk in as. Shared with Monster Hunt through localStorage,
          so picking a hero there is picking one here. */}
      <div className="mt-8 flex items-center justify-center gap-3 text-xs text-ink-mute">
        <div className="hanko-hero-chip flex items-center justify-center rounded-control border border-line bg-surface">
          <FighterSprite slug={hero} state="idle" preload={["idle"]} />
        </div>
        <span>{CHARACTER_NAMES[hero] ?? hero}</span>
        <Link href="/decks/review" className="flex items-center gap-1 font-medium text-seal">
          <ArrowLeft size={12} /> {T.exitBattle}
        </Link>
      </div>
    </div>
  );
}
