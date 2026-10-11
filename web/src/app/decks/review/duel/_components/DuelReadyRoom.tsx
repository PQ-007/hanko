"use client";

import { useEffect, useState } from "react";
import { Check, Loader2 } from "@/ui/icons";
import { T } from "../../../_lib/strings";
import type { HeadToHead } from "../../../_lib/social";
import { shouldStart } from "../_lib/chat";
import type { DuelChat } from "../_lib/useDuelChat";
import ChatFighter from "./ChatFighter";
import DuelChatPanel from "./DuelChatPanel";
import H2HRecord from "./H2HRecord";

/**
 * Before a PvP match: who is across from you, your record with them, and a
 * moment to say hello. The match starts when both press Ready, or at the
 * deadline whatever happens (readyDeadline: matches.started_at + 30 s, the
 * same moment on both screens) — so nobody can hold the other hostage.
 *
 * Starting is each client's own call; the first to begin round 1 fixes its
 * server start time for both (begin_round), so a client a second late just
 * gets a slightly shorter first round, as any late joiner would.
 */
export default function DuelReadyRoom({
  heroSlug,
  youName,
  foeSlug,
  foeName,
  foeSub,
  record,
  chat,
  deadline,
  onStart,
}: {
  heroSlug: string;
  youName: string;
  foeSlug: string;
  foeName: string;
  /** "@handle · ELO" under the name, when there is something to say. */
  foeSub?: string | null;
  /** Null while it is still loading. */
  record: HeadToHead | null;
  chat: DuelChat;
  /** Epoch ms at which the match starts regardless. */
  deadline: number;
  onStart: () => void;
}) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(id);
  }, []);

  const go = shouldStart(chat.meReady, chat.foeReady, now, deadline);
  useEffect(() => {
    if (go) onStart();
  }, [go, onStart]);

  const left = Math.max(0, Math.ceil((deadline - now) / 1000));

  return (
    // overflow-x-clip: a sprite's transparent overhang (a long weapon's reach)
    // can poke past a phone's edge and make the whole page scroll sideways.
    // w-full: sized by the screen, not by its content — the phrase row's
    // natural width is the whole row, which would otherwise widen the card
    // past a phone's edge instead of scrolling.
    <div className="mx-auto flex w-full min-h-full max-w-2xl flex-col justify-center overflow-x-clip px-2 py-4 pt-[max(1rem,env(safe-area-inset-top))] sm:px-4">
      <div className="hk-arena flex flex-col gap-4 p-4 sm:p-7">
        <p className="text-center text-[11px] font-semibold uppercase tracking-[0.16em] text-paper/40">
          {T.duelIntroKicker}
        </p>

        {/* minmax(0,1fr), not 1fr: a 1fr column won't shrink below its
            content, and the sprite overhangs its slot (wider than the slot on
            a tablet), which pushed the opponent out past the card's edge. */}
        <div className="grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-x-2 gap-y-1 sm:gap-x-6">
          <ChatFighter slug={heroSlug} base="idle" beat={chat.mine} slotClass="hanko-fighter-slot hanko-fighter-slot-compact" />
          <span className="text-2xl font-black tracking-wider text-paper/30">VS</span>
          <ChatFighter slug={foeSlug} base="idle" flip beat={chat.foe} slotClass="hanko-fighter-slot hanko-fighter-slot-compact" />

          <span className="flex min-w-0 flex-col items-center self-start text-center">
            <span className="max-w-full truncate text-sm font-bold text-paper">{youName}</span>
            <ReadyTag ready={chat.meReady} />
          </span>
          <span />
          <span className="flex min-w-0 flex-col items-center self-start text-center">
            <span className="max-w-full truncate text-sm font-bold text-paper">{foeName}</span>
            {foeSub && <span className="max-w-full truncate text-[11px] text-paper/45">{foeSub}</span>}
            <ReadyTag ready={chat.foeReady} away={!chat.foePresent} />
          </span>
        </div>

        {record ? (
          <H2HRecord record={record} youName={youName} themName={foeName} compact />
        ) : (
          <div className="h-20 animate-pulse rounded-card bg-white/5" />
        )}

        <DuelChatPanel chat={chat} foeName={foeName} />

        <div className="flex flex-col items-center gap-2">
          <button
            type="button"
            onClick={() => chat.setReady(!chat.meReady)}
            className={`hk-btn w-full max-w-xs px-6 py-3 text-base font-bold ${
              chat.meReady
                ? "border border-white/20 bg-white/10 text-paper hover:bg-white/15"
                : "hk-btn-primary"
            }`}
          >
            {chat.meReady ? (
              <>
                <Loader2 size={16} className="animate-spin" /> {T.duelWaitingFoe}
              </>
            ) : (
              <>
                <Check size={16} /> {T.duelReady}
              </>
            )}
          </button>
          <p className="text-xs font-medium tabular-nums text-paper/55">
            {go ? T.duelIntroGo : T.duelReadyAuto(left)}
          </p>
        </div>
      </div>
    </div>
  );
}

function ReadyTag({ ready, away = false }: { ready: boolean; away?: boolean }) {
  if (ready) {
    return (
      <span className="mt-1 inline-flex items-center gap-1 rounded-full bg-emerald-400/15 px-2 py-0.5 text-[11px] font-bold text-emerald-300">
        <Check size={11} /> {T.duelFoeReady}
      </span>
    );
  }
  return (
    <span className="mt-1 inline-flex items-center gap-1 rounded-full bg-white/5 px-2 py-0.5 text-[11px] font-medium text-paper/45">
      {away ? T.duelFoeAway : T.duelFoeWaiting}
    </span>
  );
}
