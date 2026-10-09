"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "../../../_lib/db";
import type { MatchRow } from "./match";

// The "again" button's state, for the result screen of a PvP match.
//
// The server side is duel_rematch(match) (0030): whoever presses first creates
// an invitation, whoever presses second starts the match. This hook just
// reflects that, from both sides:
//   idle      nobody has asked
//   waiting   I asked; they haven't answered yet
//   incoming  they asked; I can accept (pressing the same button does)
// and calls onStarted the moment the rematch is active — whichever of us
// pressed last.
//
// Realtime would be nicer, but a poll is the part that can't silently not
// work (a table missing from the publication just never fires); the channel
// only makes it quicker.

export type RematchState = "idle" | "sending" | "waiting" | "incoming";

export function useRematch({
  matchId,
  meId,
  hero,
  onStarted,
}: {
  matchId: string;
  meId: string;
  hero: string;
  onStarted: (match: MatchRow) => void;
}) {
  const [row, setRow] = useState<MatchRow | null>(null);
  const [sending, setSending] = useState(false);
  const [failed, setFailed] = useState(false);
  const started = useRef(false);
  const startedCb = useRef(onStarted);
  useEffect(() => {
    startedCb.current = onStarted;
  });

  const apply = useCallback((m: MatchRow | null) => {
    setRow(m);
    if (m && m.status === "active" && !started.current) {
      started.current = true;
      startedCb.current(m);
    }
  }, []);

  const refresh = useCallback(async () => {
    const { data } = await supabase
      .from("matches")
      .select("*")
      .eq("rematch_of", matchId)
      .in("status", ["lobby", "active"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    apply((data as MatchRow | null) ?? null);
  }, [matchId, apply]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- initial read
    void refresh();
    const channel = supabase
      .channel(`rematch:${matchId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "matches", filter: `rematch_of=eq.${matchId}` }, () => void refresh())
      .subscribe();
    const poll = setInterval(refresh, 2500);
    return () => {
      clearInterval(poll);
      supabase.removeChannel(channel);
    };
  }, [matchId, refresh]);

  const request = useCallback(async () => {
    setSending(true);
    setFailed(false);
    const { data, error } = await supabase.rpc("duel_rematch", { p_match_id: matchId, p_character: hero });
    setSending(false);
    if (error || !data) return setFailed(true);
    apply(data as MatchRow);
  }, [matchId, hero, apply]);

  /** Withdraw my request, or turn down theirs. */
  const cancel = useCallback(async () => {
    if (!row) return;
    if (row.host_id === meId) await supabase.rpc("concede_match", { p_match_id: row.id });
    else await supabase.rpc("decline_duel_invite", { p_match_id: row.id });
    setRow(null);
  }, [row, meId]);

  const state: RematchState = sending
    ? "sending"
    : row && row.status === "lobby"
      ? row.host_id === meId
        ? "waiting"
        : "incoming"
      : "idle";

  return { state, failed, request, cancel };
}
