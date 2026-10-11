"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase } from "../../../_lib/db";
import {
  acceptIncoming,
  acceptReady,
  allowMessage,
  CHAT_EVENT,
  chatTopic,
  READY_EVENT,
  cleanText,
  displayText,
  type ChatKind,
  type ChatPayload,
} from "./chat";

export interface ChatEntry {
  key: number;
  mine: boolean;
  kind: ChatKind;
  text: string;
}

/** The latest thing a side said or did, for its fighter's bubble and pose. */
export interface Beat {
  nonce: number;
  text: string;
  /** Set for an emote: which one, so the fighter can play it. */
  emote: string | null;
}

export interface DuelChat {
  entries: ChatEntry[];
  mine: Beat | null;
  foe: Beat | null;
  meReady: boolean;
  foeReady: boolean;
  /** The opponent's screen is on the channel (presence). */
  foePresent: boolean;
  canType: boolean;
  send: (kind: ChatKind, value: string) => boolean;
  setReady: (ready: boolean) => void;
}

/**
 * One Realtime channel per match, alive from the ready room to the result
 * screen: broadcast for messages, presence for "ready". See chat.ts for why
 * the receiving side is the one that enforces the rules.
 */
export function useDuelChat(
  opts: { matchId: string; meId: string; opponentId: string; isFriend: boolean } | null
): DuelChat {
  // Null for a bot match: no channel, nothing to say to a bot.
  const matchId = opts?.matchId ?? "";
  const meId = opts?.meId ?? "";
  const opponentId = opts?.opponentId ?? "";
  const isFriend = opts?.isFriend ?? false;
  const [entries, setEntries] = useState<ChatEntry[]>([]);
  const [mine, setMine] = useState<Beat | null>(null);
  const [foe, setFoe] = useState<Beat | null>(null);
  const [meReady, setMeReady] = useState(false);
  const [foeReady, setFoeReady] = useState(false);
  const [foePresent, setFoePresent] = useState(false);

  const channel = useRef<RealtimeChannel | null>(null);
  const subscribed = useRef(false);
  const ready = useRef(false);
  const sent = useRef<number[]>([]);
  const received = useRef<number[]>([]);
  const nonce = useRef(0);
  const isFriendRef = useRef(isFriend);
  useEffect(() => {
    isFriendRef.current = isFriend;
  }, [isFriend]);

  const push = useCallback((p: ChatPayload, isMine: boolean) => {
    const text = displayText(p);
    if (!text) return;
    const key = ++nonce.current;
    // The log keeps the last 40; a match's worth of chat, not an archive.
    setEntries((e) => [...e.slice(-39), { key, mine: isMine, kind: p.kind, text }]);
    const beat = { nonce: key, text, emote: p.kind === "emote" ? (p.id ?? null) : null };
    (isMine ? setMine : setFoe)(beat);
  }, []);

  useEffect(() => {
    if (!matchId) return;
    const ch = supabase.channel(chatTopic(matchId), {
      config: { broadcast: { self: false }, presence: { key: meId } },
    });
    channel.current = ch;

    ch.on("broadcast", { event: CHAT_EVENT }, ({ payload }) => {
      const p = acceptIncoming(payload, { opponentId, isFriend: isFriendRef.current });
      if (!p || !allowMessage(received.current, Date.now())) return;
      push(p, false);
    });
    ch.on("broadcast", { event: READY_EVENT }, ({ payload }) => {
      const r = acceptReady(payload, opponentId);
      if (r === null) return;
      setFoeReady(r);
      setFoePresent(true);
    });
    ch.on("presence", { event: "sync" }, () => {
      const metas = Object.values(ch.presenceState()).flat() as unknown as { user?: string; ready?: boolean }[];
      const theirs = metas.filter((m) => m.user === opponentId);
      setFoePresent(theirs.length > 0);
      setFoeReady(theirs.some((m) => m.ready === true));
    });
    ch.subscribe((status) => {
      subscribed.current = status === "SUBSCRIBED";
      if (subscribed.current) void ch.track({ user: meId, ready: ready.current });
    });

    return () => {
      subscribed.current = false;
      channel.current = null;
      void supabase.removeChannel(ch);
    };
  }, [matchId, meId, opponentId, push]);

  const send = useCallback(
    (kind: ChatKind, value: string) => {
      const ch = channel.current;
      if (!ch) return false;
      if (kind === "text" && !isFriendRef.current) return false;
      const payload: ChatPayload =
        kind === "text" ? { v: 1, from: meId, kind, text: cleanText(value) } : { v: 1, from: meId, kind, id: value };
      if (kind === "text" && !payload.text) return false;
      if (!allowMessage(sent.current, Date.now())) return false;
      push(payload, true);
      void ch.send({ type: "broadcast", event: CHAT_EVENT, payload });
      return true;
    },
    [meId, push]
  );

  const setReady = useCallback(
    (value: boolean) => {
      ready.current = value;
      setMeReady(value);
      const ch = channel.current;
      if (!ch || !subscribed.current) return;
      void ch.send({ type: "broadcast", event: READY_EVENT, payload: { v: 1, from: meId, ready: value } });
      void ch.track({ user: meId, ready: value });
    },
    [meId]
  );

  return { entries, mine, foe, meReady, foeReady, foePresent, canType: isFriend, send, setReady };
}
