"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Bot, Copy, Loader2, LogIn, Swords, Users } from "lucide-react";
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
import DuelArena from "./DuelArena";

interface MatchRow {
  id: string;
  join_code: string | null;
  host_id: string;
  guest_id: string | null;
  host_character: string;
  guest_character: string | null;
  host_baseline_ms: number | null;
  guest_baseline_ms: number | null;
  status: string;
  round_count: number;
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
    await supabase.rpc("forfeit_match", { p_match_id: match.id });
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
    if (!match || match.status !== "active" || !userId) return null;
    const isHost = match.host_id === userId;
    const opponentId = isHost ? match.guest_id : match.host_id;
    if (!opponentId) return null;
    const spec: RemoteMatch = {
      matchId: match.id,
      opponentId,
      name: T.multiplayerTitle,
      slug: (isHost ? match.guest_character : match.host_character) ?? "knight",
      baselineMs: (isHost ? match.guest_baseline_ms : match.host_baseline_ms) ?? null,
    };
    return createRemoteOpponent(spec);
  }, [match, userId]);

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

  if (remoteOpponent && match) {
    return (
      <DuelArena
        key={match.id}
        opponent={remoteOpponent}
        roundCount={match.round_count}
      />
    );
  }

  // Host waiting room.
  if (match && match.status === "lobby") {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center">
        <Loader2 size={24} className="mx-auto animate-spin text-ink-mute" />
        <h1 className="mt-5 text-xl font-bold text-ink">{T.duelWaitingGuest}</h1>
        <p className="mt-1 text-sm text-ink-soft">{T.duelCodeShare}</p>
        <button
          onClick={() => navigator.clipboard?.writeText(match.join_code ?? "")}
          className="mt-6 flex w-full items-center justify-center gap-3 rounded-card border border-line bg-white py-6 text-4xl font-extrabold tracking-[0.3em] text-ink transition hover:bg-paper-dim"
        >
          {match.join_code}
          <Copy size={18} className="text-ink-mute" />
        </button>
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

      <section className="mt-7">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-ink">
          <Bot size={16} className="text-seal" /> {T.duelBotSection}
        </h2>
        <p className="mt-0.5 text-xs text-ink-mute">{T.duelBotDesc}</p>
        <div className="mt-3 grid gap-2 sm:grid-cols-3">
          {BOT_DIFFICULTIES.map((d) => (
            <button
              key={d}
              onClick={() => startBot(d)}
              className="hk-card hk-card-interactive group flex flex-col items-center gap-2 px-4 py-5 text-center"
            >
              <span className="text-sm font-semibold text-ink">{BOT_LABEL[d].name}</span>
              <span className="text-xs leading-relaxed text-ink-mute">{BOT_LABEL[d].desc}</span>
              <span className="mt-1 flex items-center gap-1 text-[11px] font-medium text-seal">
                <Swords size={12} /> {T.practiceStart}
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

        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
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
            className="flex-1 rounded-control border border-line bg-white px-4 py-3 text-center text-lg font-bold tracking-[0.3em] uppercase focus:border-seal focus:outline-none focus:ring-2 focus:ring-seal-tint"
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
        <div className="hanko-hero-chip flex items-center justify-center rounded-control border border-line bg-white">
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
