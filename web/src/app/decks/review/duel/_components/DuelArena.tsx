"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Flame } from "lucide-react";
import { supabase } from "../../../_lib/db";
import { T } from "../../../_lib/strings";
import type { QueueCard } from "../../../_lib/types";
import { buildQuiz, MIN_WORDS_FOR_BATTLE, type OwnWord, type QuizOption } from "../../battle/_lib/quiz";
import { usePlayerCharacter } from "../../battle/_lib/playerCharacter";
import { buzzCrit, buzzHit, buzzHurt, buzzVictory } from "../../battle/_lib/feedback";
import { attackPose, MAX_ATTACK_TIER, ONE_SHOT_MS, type SpriteState } from "../../battle/_lib/sprites";
import { useQuestionClock } from "../../battle/_lib/useQuestionClock";
import FighterSprite from "../../battle/_components/FighterSprite";
import BattleHpStrip from "../../battle/_components/BattleHpStrip";
import CountdownBar from "../../battle/_components/CountdownBar";
import LoadingScene from "../../battle/_components/LoadingScene";
import QuizOptions from "../../battle/_components/QuizOptions";
import {
  DUEL_MAX_HP,
  DUEL_ROUND_COUNT,
  deriveDuelState,
  duelOutcome,
  duelStreakTier,
  resolveRound,
  roundDurationMs,
  type DuelAnswer,
  type ResolvedRound,
} from "../_lib/duel";
import type { OpponentDriver } from "../_lib/opponent";
import DuelResult from "./DuelResult";

// How long the arena holds on a resolved round before the next question. Long
// enough to read both damage numbers and see who was right; short enough that
// twelve of them don't add a minute to the match.
const RESOLVE_HOLD_MS = 1500;

// The second beat of a resolution: attackers swing, then whoever took damage
// flinches. One sprite cannot be mid-attack and mid-flinch at once, and in a
// round where both sides land a hit both are true — so they are sequenced
// rather than merged.
const FLINCH_BEAT_MS = ONE_SHOT_MS;

interface ClosedRound {
  you: DuelAnswer | null;
  them: DuelAnswer | null;
}

export default function DuelArena({
  opponent,
  deckId = null,
  roundCount = DUEL_ROUND_COUNT,
  onRematch,
  exitHref = "/decks/review/duel",
}: {
  opponent: OpponentDriver;
  deckId?: string | null;
  roundCount?: number;
  onRematch?: () => void;
  exitHref?: string;
}) {
  const hero = usePlayerCharacter();

  const [cards, setCards] = useState<QueueCard[] | null>(null);
  const [allWords, setAllWords] = useState<OwnWord[] | null>(null);
  // The player's own median response time (response_baseline, 0020). Null is a
  // legitimate answer — too few reviews to have a personal median yet — and
  // duel.ts falls back to a constant for it, so this is never awaited on.
  const [baselineMs, setBaselineMs] = useState<number | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [rounds, setRounds] = useState<ResolvedRound[]>([]);
  const [roundNo, setRoundNo] = useState(1);
  const [phase, setPhase] = useState<"question" | "resolving">("question");
  // What the local player did this round, for the option highlight. Undefined
  // until they pick; null means the clock beat them.
  const [yourPick, setYourPick] = useState<QuizOption | null | undefined>(undefined);
  const [opponentAnswered, setOpponentAnswered] = useState(false);
  const [lastRound, setLastRound] = useState<ResolvedRound | null>(null);

  const [heroPose, setHeroPose] = useState<SpriteState>("idle");
  const [foePose, setFoePose] = useState<SpriteState>("idle");

  // Resolves the local player's half of the round. Held in a ref because both
  // the pick handler and the clock's expiry callback settle it, and the clock
  // callback runs from a closure set up in an earlier render.
  const yourResolver = useRef<((a: DuelAnswer | null) => void) | null>(null);
  const answered = useRef(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [cardsRes, wordsRes, baselineRes] = await Promise.all([
        // practice_cards, NOT review_queue: the scheduled queue is capped by
        // the day's remaining allowance (0010), so a duel wired through it
        // would be unplayable on exactly the day a player has finished their
        // reviews and wants to play something.
        supabase.rpc("practice_cards", { p_deck_id: deckId, p_limit: 60 }),
        supabase
          .from("words")
          .select("id, term, reading, meaning, meaning_mn")
          .eq("deleted", false),
        supabase.rpc("response_baseline"),
      ]);
      if (cancelled) return;
      if (cardsRes.error) setLoadError(cardsRes.error.message);
      setCards((cardsRes.data as QueueCard[]) ?? []);
      setAllWords((wordsRes.data as OwnWord[]) ?? []);
      // A missing RPC (migration not applied) degrades to the constant rather
      // than failing the match.
      setBaselineMs(baselineRes.error ? null : ((baselineRes.data as number | null) ?? null));
    })();
    return () => {
      cancelled = true;
    };
  }, [deckId]);

  const state = useMemo(() => deriveDuelState(rounds), [rounds]);
  const outcome = duelOutcome(state, roundCount);
  const durationMs = roundDurationMs(roundNo);

  // Wraps rather than running out: practice_cards returns up to 60 random
  // cards and a match is twelve rounds, so this only bites for a library
  // smaller than the round count — where repeating a word is still a better
  // match than ending early.
  const card = cards && cards.length > 0 ? cards[(roundNo - 1) % cards.length] : null;

  const quiz = useMemo<QuizOption[] | null>(() => {
    if (!card || !allWords) return null;
    return buildQuiz(card, allWords);
    // roundNo is a dependency on purpose: a wrapped card would otherwise keep
    // the identical shuffle it had the first time round.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [card, allWords, roundNo]);

  const ready = cards !== null && allWords !== null && quiz !== null;
  const tooFewWords = allWords !== null && allWords.length < MIN_WORDS_FOR_BATTLE;

  const { remainingMs, elapsedMs } = useQuestionClock({
    durationMs,
    resetKey: roundNo,
    running: ready && phase === "question" && outcome === "ongoing",
    onExpire: () => {
      if (answered.current) return; // already picked; we're only waiting on them
      answered.current = true;
      setYourPick(null);
      yourResolver.current?.(null);
      // A timeout is submitted too, not left absent. It means the same thing
      // to the scheduler and to damage — nothing — but a row that exists is
      // what lets the opponent's client stop waiting at the buzzer instead of
      // polling for something that will never arrive.
      opponentRef.current.submit?.(roundNoRef.current, null, cardRef.current?.card_id ?? null)
        ?.catch(() => {});
    },
  });

  // Read by closeRound and handlePick, both of which can run from a closure
  // set up in an earlier render — the round's promise settles whenever the
  // opponent gets round to answering, and by then the captured values would be
  // stale. Synced from an effect rather than assigned during render: writing a
  // ref while rendering is the thing that makes a component miss updates.
  // Declared above the round effect so it commits first on the same render.
  const cardRef = useRef<QueueCard | null>(null);
  const baselineRef = useRef<number | null>(null);
  const stateRef = useRef(state);
  const roundNoRef = useRef(roundNo);
  const opponentRef = useRef(opponent);
  useEffect(() => {
    cardRef.current = card;
    baselineRef.current = baselineMs;
    stateRef.current = state;
    roundNoRef.current = roundNo;
    opponentRef.current = opponent;
  });

  const closeRound = useCallback(
    ({ you, them }: ClosedRound) => {
      const resolved = resolveRound(
        roundNo,
        you,
        them,
        baselineRef.current,
        opponent.baselineMs,
        stateRef.current
      );

      setRounds((prev) => [...prev, resolved]);
      setLastRound(resolved);
      setPhase("resolving");

      // Beat one: whoever landed a hit swings.
      const tier = Math.min(MAX_ATTACK_TIER, duelStreakTier(stateRef.current.yourStreak));
      if (resolved.yourDamage > 0) setHeroPose(attackPose(hero, tier));
      if (resolved.theirDamage > 0) setFoePose(attackPose(opponent.slug, 0));

      if (resolved.yourDamage > 0) {
        if (duelStreakTier(stateRef.current.yourStreak) > 0) buzzCrit();
        else buzzHit();
      } else if (resolved.theirDamage > 0) {
        buzzHurt();
      }
      return resolved;
    },
    [roundNo, opponent.baselineMs, opponent.slug, hero]
  );

  // One round, start to finish. Both halves are bounded by the round timer, so
  // this always settles — see the contract on OpponentDriver.
  useEffect(() => {
    if (!ready || phase !== "question" || outcome !== "ongoing") return;

    let cancelled = false;
    const controller = new AbortController();
    answered.current = false;

    const yours = new Promise<DuelAnswer | null>((resolve) => {
      yourResolver.current = resolve;
    });
    const theirs = opponent
      .answerFor(roundNo, durationMs, controller.signal)
      .then((a) => {
        if (!cancelled) setOpponentAnswered(true);
        return a;
      });

    Promise.all([yours, theirs]).then(([you, them]) => {
      if (cancelled) return;
      closeRound({ you, them });
    });

    return () => {
      cancelled = true;
      controller.abort();
      yourResolver.current = null;
    };
    // closeRound is deliberately not a dependency: it is rebuilt whenever the
    // derived state changes, and listing it would abort and restart the round
    // — cancelling the opponent's pending answer — every time HP moved.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, phase, outcome, roundNo, durationMs, opponent]);

  // Beat two: the flinch, once the swings have played.
  useEffect(() => {
    if (phase !== "resolving" || !lastRound) return;
    const id = setTimeout(() => {
      if (lastRound.yourDamage > 0) setFoePose("hurt");
      if (lastRound.theirDamage > 0) setHeroPose("hurt");
    }, FLINCH_BEAT_MS);
    return () => clearTimeout(id);
  }, [phase, lastRound]);

  // ...and then the next round, unless the match is over.
  useEffect(() => {
    if (phase !== "resolving") return;
    if (outcome !== "ongoing") {
      if (outcome === "won") buzzVictory();
      return;
    }
    const id = setTimeout(() => {
      setRoundNo((n) => n + 1);
      setPhase("question");
      setHeroPose("idle");
      setFoePose("idle");
      // The per-round reset lives here rather than at the top of the round
      // effect: round 1 already starts at these values, and doing it there is
      // a synchronous setState inside an effect body.
      setYourPick(undefined);
      setOpponentAnswered(false);
    }, RESOLVE_HOLD_MS);
    return () => clearTimeout(id);
  }, [phase, outcome]);

  function handlePick(option: QuizOption) {
    if (answered.current || phase !== "question") return;
    answered.current = true;
    const answer: DuelAnswer = { correct: option.correct, elapsedMs: elapsedMs() };
    setYourPick(option);
    yourResolver.current?.(answer);

    const played = cardRef.current;
    if (played) {
      // Logged, never scheduled. review_card()'s log-only branch (0018) returns
      // the card untouched for source='battle' — enforced server-side rather
      // than trusted to callers, so a bug here cannot corrupt SM-2.
      //
      // Deliberately not awaited: a duel is real-time, and a slow insert must
      // not delay the round. A dropped log costs a row of analytics; a stalled
      // round costs the match.
      supabase
        .rpc("review_card", {
          p_card_id: played.card_id,
          p_rating: option.correct ? "good" : "again",
          p_duration_ms: answer.elapsedMs,
          p_log_id: crypto.randomUUID(),
          p_source: "battle",
        })
        .then(undefined, () => {});
      opponent.submit?.(roundNo, answer, played.card_id)?.catch(() => {});
    }
  }

  // Keyboard: 1-4 and A-D, matching the badges QuizOptions draws — the same
  // bindings the arena next door uses, so the two modes don't need learning
  // separately. No pause and no undo: neither is meaningful against an
  // opponent who is not waiting for you.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement | null;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) return;
      if (!quiz || phase !== "question" || answered.current || outcome !== "ongoing") return;
      const key = e.key.toLowerCase();
      const index = "1234".indexOf(key) >= 0 ? Number(key) - 1 : "abcd".indexOf(key);
      if (index < 0 || index >= quiz.length) return;
      e.preventDefault();
      handlePick(quiz[index]);
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [quiz, phase, outcome]);

  useEffect(() => {
    const driver = opponent;
    return () => driver.dispose?.();
  }, [opponent]);

  if (loadError) {
    return (
      <p className="mx-auto max-w-md rounded-control bg-red-500/15 px-4 py-3 text-center text-sm text-red-200 ring-1 ring-red-400/30">
        {T.duelLoadFailed}
      </p>
    );
  }
  if (tooFewWords) {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center">
        <p className="text-sm text-ink-soft">{T.notEnoughWordsBattle}</p>
        <Link href="/decks" className="mt-5 hk-btn hk-btn-primary px-5 py-2.5 text-sm">
          {T.decksNav}
        </Link>
      </div>
    );
  }
  if (!ready) return <LoadingScene label={T.duelLoading} />;

  if (outcome !== "ongoing") {
    return (
      <DuelResult
        outcome={outcome}
        rounds={rounds}
        state={state}
        opponentName={opponent.name}
        opponentSlug={opponent.slug}
        hero={hero}
        onRematch={onRematch}
        exitHref={exitHref}
      />
    );
  }

  const heroDisplayPose = state.yourDefeated ? "death" : heroPose;
  const foeDisplayPose = state.theirDefeated ? "death" : foePose;

  return (
    <div className="mx-auto flex min-h-[calc(100vh-8rem)] max-w-5xl flex-col justify-center px-4 py-6 sm:py-8 xl:max-w-7xl">
      <div className="hk-arena relative flex flex-col gap-4 p-4 sm:p-6">
        <div className="flex items-center justify-between gap-2 text-xs">
          <Link
            href={exitHref}
            className="flex items-center gap-1 rounded-control px-2 py-1 font-medium text-paper/60 transition hover:bg-white/10 hover:text-paper"
          >
            <ArrowLeft size={13} /> {T.exitBattle}
          </Link>
          <div className="flex items-center gap-2">
            {state.yourStreak >= 3 && (
              <span className="flex items-center gap-1 rounded-full bg-amber-400/15 px-2 py-1 font-medium text-amber-200 ring-1 ring-amber-400/30">
                <Flame size={12} /> {T.duelStreakLabel(state.yourStreak)}
              </span>
            )}
            <span className="rounded-full bg-white/10 px-2 py-1 font-medium text-paper/80 tabular-nums">
              {T.duelRoundOf(roundNo, roundCount)}
            </span>
          </div>
        </div>

        <div className="flex items-center justify-between gap-3 text-[11px] font-semibold uppercase tracking-wider text-paper/50">
          <span>{T.duelYou}</span>
          <span>{opponent.name}</span>
        </div>

        <BattleHpStrip
          playerHp={state.yourHp}
          monsterHp={state.theirHp}
          maxHp={DUEL_MAX_HP}
        />

        {/* Fixed height so the stage never shifts between the question and the
            resolution. */}
        <div className="flex h-8 items-center justify-center gap-4 text-sm">
          {phase === "question" ? (
            yourPick !== undefined ? (
              <span className="text-paper/60">{T.duelWaitingAnswer}</span>
            ) : opponentAnswered ? (
              <span className="font-medium text-amber-300">{T.duelOpponentAnswered}</span>
            ) : (
              <span className="text-paper/40">{T.duelOpponentThinking}</span>
            )
          ) : (
            lastRound && (
              <>
                <span
                  className={`font-semibold ${
                    lastRound.you?.correct ? "text-emerald-400" : "text-red-400"
                  }`}
                >
                  {T.duelYou} {lastRound.yourDamage > 0 ? `−${lastRound.yourDamage}` : "—"}
                </span>
                <span
                  className={`font-semibold ${
                    lastRound.them?.correct ? "text-emerald-400" : "text-red-400"
                  }`}
                >
                  {opponent.name} {lastRound.theirDamage > 0 ? `−${lastRound.theirDamage}` : "—"}
                </span>
              </>
            )
          )}
        </div>

        <div className="relative flex flex-wrap items-center justify-center gap-3 lg:h-[420px] lg:flex-nowrap lg:gap-4 xl:h-[460px]">
          <div className="hanko-fighter-slot relative order-1 flex shrink-0 items-center justify-center">
            <FighterSprite
              slug={hero}
              state={heroDisplayPose}
              onOneShotEnd={() => setHeroPose("idle")}
            />
          </div>

          <div className="hanko-fighter-slot relative order-2 flex shrink-0 items-center justify-center lg:order-3">
            <FighterSprite
              slug={opponent.slug}
              state={foeDisplayPose}
              flip
              onOneShotEnd={() => setFoePose("idle")}
            />
          </div>

          <div className="relative z-10 order-3 flex w-full shrink-0 items-center justify-center lg:order-2 lg:h-full lg:w-[430px] xl:w-[490px]">
            <div className="hanko-parchment flex w-full flex-col gap-4 px-6 py-8 text-center sm:px-8 xl:gap-5 xl:px-10 xl:py-10">
              <div className="text-4xl font-bold tracking-tight text-ink xl:text-5xl">
                {card?.term}
              </div>
              <CountdownBar
                durationMs={durationMs}
                remainingMs={phase === "question" ? remainingMs : 0}
                paused={false}
              />
              <QuizOptions
                options={quiz}
                disabled={phase !== "question" || yourPick !== undefined}
                onPick={handlePick}
              />
            </div>
          </div>
        </div>

        <p className="text-center text-[11px] text-paper/35">{T.duelNotScheduled}</p>
      </div>
    </div>
  );
}
