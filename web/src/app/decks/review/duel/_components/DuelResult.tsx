"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, RotateCcw } from "@/ui/icons";
import { T } from "../../../_lib/strings";
import type { HeadToHead } from "../../../_lib/social";
import FighterSprite from "../../battle/_components/FighterSprite";
import type { DuelOutcome, DuelState, ResolvedRound } from "../_lib/duel";
import type { MatchRow } from "../_lib/match";
import { loadRecord, recordTotal } from "../_lib/record";
import { useRematch } from "../_lib/useRematch";
import H2HRecord from "./H2HRecord";

/** What the result screen needs to show a person-vs-person ending. */
export interface OnlineResult {
  matchId: string;
  meId: string;
  opponentId: string;
  /** Your record BEFORE this match (it is added to once the match is written). */
  before: HeadToHead | null;
  onRematchStarted: (match: MatchRow) => void;
}

// Derived here rather than tracked during the match, the same way
// BattleResult reads the raw event log: the arena should not carry state that
// only matters once the fight is over.
function summarise(rounds: ResolvedRound[]) {
  let correct = 0;
  let damage = 0;
  let streak = 0;
  let bestStreak = 0;
  for (const r of rounds) {
    damage += r.yourDamage;
    if (r.you?.correct) {
      correct++;
      streak++;
      bestStreak = Math.max(bestStreak, streak);
    } else {
      streak = 0;
    }
  }
  return { correct, damage, bestStreak };
}

function Tile({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-control bg-white/5 px-3 py-3 text-center ring-1 ring-white/10">
      <div className="text-2xl font-bold tabular-nums text-paper">{value}</div>
      <div className="mt-0.5 text-[11px] font-medium text-paper/50">{label}</div>
    </div>
  );
}

export default function DuelResult({
  outcome,
  rounds,
  state,
  opponentName,
  opponentSlug,
  hero,
  onRematch,
  exitHref,
  opponentLeft = false,
  online,
}: {
  outcome: DuelOutcome;
  rounds: ResolvedRound[];
  state: DuelState;
  opponentName: string;
  opponentSlug: string;
  hero: string;
  onRematch?: () => void;
  exitHref: string;
  /** The win came from the other player leaving, not from the fight. */
  opponentLeft?: boolean;
  /** Set for a match against a person: record, and a rematch that asks them. */
  online?: OnlineResult;
}) {
  const { correct, damage, bestStreak } = summarise(rounds);

  const title =
    outcome === "won" ? T.duelWon : outcome === "lost" ? T.duelLost : T.duelDraw;
  const desc =
    outcome === "won"
      ? opponentLeft
        ? T.duelOpponentLeft
        : T.duelWonDesc
      : outcome === "lost"
        ? T.duelLostDesc
        : T.duelDrawDesc;
  const tone =
    outcome === "won"
      ? "text-emerald-400"
      : outcome === "lost"
        ? "text-red-400"
        : "text-amber-300";

  return (
    <div className="mx-auto flex min-h-full max-w-3xl flex-col justify-center px-4 py-8">
      <div className="hk-arena flex flex-col gap-6 p-6 sm:p-8">
        <div className="text-center">
          <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-paper/40">
            {T.duelKicker}
          </p>
          <h1 className={`mt-1 text-3xl font-extrabold tracking-tight ${tone}`}>{title}</h1>
          <p className="mt-1 text-sm text-paper/55">{desc}</p>
        </div>

        {/* The two fighters as they finished. A draw leaves both standing,
            which is the whole visual difference between it and a win. */}
        <div className="flex items-center justify-center gap-6">
          <div className="hanko-fighter-slot flex shrink-0 items-center justify-center">
            <FighterSprite
              slug={hero}
              state={state.yourDefeated ? "death" : "idle"}
              preload={["idle", "death"]}
            />
          </div>
          <span className="text-xs font-bold tracking-wider text-paper/40">VS</span>
          <div className="hanko-fighter-slot flex shrink-0 items-center justify-center">
            <FighterSprite
              slug={opponentSlug}
              state={state.theirDefeated ? "death" : "idle"}
              flip
              preload={["idle", "death"]}
            />
          </div>
        </div>

        <div className="flex items-center justify-center gap-4 text-sm font-semibold tabular-nums">
          <span className="text-paper">
            {T.duelYou} {Math.max(0, state.yourHp)}
          </span>
          <span className="text-paper/30">·</span>
          <span className="text-paper">
            {opponentName} {Math.max(0, state.theirHp)}
          </span>
        </div>

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Tile label={T.duelResultRounds} value={rounds.length} />
          <Tile label={T.duelResultCorrect} value={correct} />
          <Tile label={T.duelResultBestStreak} value={bestStreak} />
          <Tile label={T.duelResultDamage} value={damage} />
        </div>

        {online ? (
          <OnlineEnd online={online} hero={hero} opponentName={opponentName} exitHref={exitHref} />
        ) : (
          <div className="flex flex-col gap-2 sm:flex-row sm:justify-center">
            {onRematch && (
              <button onClick={onRematch} className="hk-btn hk-btn-primary px-5 py-2.5 text-sm">
                <RotateCcw size={15} /> {T.duelRematch}
              </button>
            )}
            <ExitLink href={exitHref} />
          </div>
        )}
      </div>
    </div>
  );
}

function ExitLink({ href }: { href: string }) {
  return (
    <Link
      href={href}
      className="hk-btn border border-white/15 bg-white/5 px-5 py-2.5 text-sm text-paper hover:bg-white/10"
    >
      <ArrowLeft size={15} /> {T.exitBattle}
    </Link>
  );
}

/**
 * The ending of a match against a person: your record with them (this match
 * included, once it has been written — the last round's resolve_round is what
 * finishes it, so it is polled for a moment), and the "again" button.
 */
function OnlineEnd({
  online,
  hero,
  opponentName,
  exitHref,
}: {
  online: OnlineResult;
  hero: string;
  opponentName: string;
  exitHref: string;
}) {
  const [record, setRecord] = useState<HeadToHead | null>(online.before);
  const wanted = online.before ? recordTotal(online.before) + 1 : 1;

  useEffect(() => {
    let cancelled = false;
    let tries = 0;
    const load = async () => {
      const r = await loadRecord(online.meId, online.opponentId);
      if (cancelled) return;
      if (recordTotal(r) >= wanted || tries >= 6) setRecord(r);
      else {
        tries++;
        setTimeout(load, 1200);
      }
    };
    void load();
    return () => {
      cancelled = true;
    };
  }, [online.meId, online.opponentId, wanted]);

  const { state, failed, request, cancel } = useRematch({
    matchId: online.matchId,
    meId: online.meId,
    hero,
    onStarted: online.onRematchStarted,
  });

  return (
    <>
      {record && <H2HRecord record={record} youName={T.duelYou} themName={opponentName} compact />}

      {state === "incoming" && (
        <p className="text-center text-sm font-semibold text-amber-200">{T.duelRematchIncoming(opponentName)}</p>
      )}
      {failed && <p className="text-center text-xs text-red-300">{T.duelRematchFailed}</p>}

      <div className="flex flex-col gap-2 sm:flex-row sm:justify-center">
        {state === "waiting" ? (
          <>
            <span className="hk-btn cursor-default bg-white/10 px-5 py-2.5 text-sm text-paper/80">
              <Loader2 size={15} className="animate-spin" /> {T.duelRematchWaiting(opponentName)}
            </span>
            <button
              onClick={cancel}
              className="hk-btn border border-white/15 bg-white/5 px-5 py-2.5 text-sm text-paper hover:bg-white/10"
            >
              {T.duelRematchCancel}
            </button>
            <ExitLink href={exitHref} />
          </>
        ) : (
          <>
            <button
              onClick={request}
              disabled={state === "sending"}
              className="hk-btn hk-btn-primary px-5 py-2.5 text-sm disabled:opacity-60"
            >
              {state === "sending" ? <Loader2 size={15} className="animate-spin" /> : <RotateCcw size={15} />}
              {state === "incoming" ? T.duelInviteAccept : T.duelRematch}
            </button>
            {state === "incoming" && (
              <button
                onClick={cancel}
                className="hk-btn border border-white/15 bg-white/5 px-5 py-2.5 text-sm text-paper hover:bg-white/10"
              >
                {T.duelInviteDecline}
              </button>
            )}
            <ExitLink href={exitHref} />
          </>
        )}
      </div>
    </>
  );
}
