import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase } from "../../../_lib/db";
import type { DuelAnswer } from "./duel";
import type { OpponentDriver } from "./opponent";

// The other half of the OpponentDriver seam: a real person on another machine.
//
// Realtime is an OPTIMISATION here, not the mechanism. Every round ends with a
// direct read of the opponent's answer row, and the round is bounded by its own
// deadline — so a channel that never connects (the commonest failure, and a
// silent one: a table missing from the supabase_realtime publication
// subscribes fine and simply never fires) costs latency, not correctness.
// Building it the other way round produces a mode that works on the developer's
// machine and hangs on everyone else's.

export interface RemoteMatch {
  matchId: string;
  opponentId: string;
  name: string;
  slug: string;
  baselineMs: number | null;
}

interface AnswerRow {
  correct: boolean;
  effective_ms: number;
}

export function createRemoteOpponent(match: RemoteMatch): OpponentDriver {
  let channel: RealtimeChannel | null = null;

  async function readAnswer(roundNo: number): Promise<AnswerRow | null> {
    const { data } = await supabase
      .from("match_answers")
      .select("correct, effective_ms")
      .eq("match_id", match.matchId)
      .eq("round_no", roundNo)
      .eq("user_id", match.opponentId)
      .maybeSingle();
    return (data as AnswerRow | null) ?? null;
  }

  return {
    name: match.name,
    slug: match.slug,
    baselineMs: match.baselineMs,

    async answerFor(roundNo, durationMs, signal) {
      // Idempotent, and whichever client gets here first fixes the round's
      // start time for both. The server's timestamp is the only clock either
      // side is allowed to trust for damage.
      const { data: round } = await supabase.rpc("begin_round", {
        p_match_id: match.matchId,
        p_round_no: roundNo,
      });

      // How much of the round is actually left, from the server's start time
      // rather than from when this client happened to render. A slow loader
      // gets a shorter round, which is the honest outcome — the alternative is
      // two players answering the same round against different deadlines.
      const startedAt = round?.starts_at ? Date.parse(round.starts_at as string) : Date.now();
      const remainingMs = Math.max(0, (round?.duration_ms ?? durationMs) - (Date.now() - startedAt));

      const arrived = await new Promise<boolean>((resolve) => {
        if (signal.aborted) return resolve(false);
        let settled = false;
        const done = (value: boolean) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve(value);
        };
        const timer = setTimeout(() => done(false), remainingMs);
        signal.addEventListener("abort", () => done(false));

        channel = supabase
          .channel(`match:${match.matchId}:round:${roundNo}`)
          .on(
            "postgres_changes",
            {
              event: "INSERT",
              schema: "public",
              table: "match_answers",
              filter: `match_id=eq.${match.matchId}`,
            },
            (payload) => {
              const row = payload.new as { round_no: number; user_id: string };
              if (row.round_no === roundNo && row.user_id === match.opponentId) done(true);
            }
          )
          .subscribe();
      });

      if (channel) {
        supabase.removeChannel(channel);
        channel = null;
      }
      if (signal.aborted) return null;

      // Applies the round's damage server-side. Idempotent and guarded on
      // current_round, so both clients calling it is a no-op for the second —
      // and it must be called even when nobody answered, or a round both
      // players let expire would never advance the match.
      await supabase.rpc("resolve_round", {
        p_match_id: match.matchId,
        p_round_no: roundNo,
      });

      // Always re-read, whether or not the channel fired: this is the part
      // that is actually load-bearing.
      const row = await readAnswer(roundNo);
      if (!row) return null;
      void arrived;
      return { correct: row.correct, elapsedMs: row.effective_ms } satisfies DuelAnswer;
    },

    async submit(roundNo, answer, cardId) {
      await supabase.rpc("submit_round_answer", {
        p_match_id: match.matchId,
        p_round_no: roundNo,
        // A round the player let expire is submitted as an explicit wrong
        // answer rather than left absent. Both mean "no damage", but a row
        // that exists is what lets the opponent's client stop waiting the
        // moment the buzzer goes instead of polling an absence.
        p_correct: answer?.correct ?? false,
        p_client_elapsed_ms: answer?.elapsedMs ?? null,
        p_card_id: cardId,
      });
    },

    dispose() {
      if (channel) {
        supabase.removeChannel(channel);
        channel = null;
      }
    },
  };
}
