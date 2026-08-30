"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { ArrowLeft, Pause, Play, Skull, Undo2 } from "lucide-react";
import type { Rating } from "@/lib/srs";
import { usePracticeSession } from "../../../_lib/usePracticeSession";
import { supabase } from "../../../_lib/db";
import { T } from "../../../_lib/strings";
import { buildQuiz, MIN_WORDS_FOR_BATTLE, type OwnWord, type QuizOption } from "../_lib/quiz";
import {
  battleOutcome,
  deriveBattleState,
  rollEvent,
  ARMOR_STREAK_INTERVAL,
  PLAYER_MAX_HP,
  STREAK_BONUS_THRESHOLD,
  type BattleEvent,
} from "../_lib/damage";
import { pickMonster } from "../_lib/monsters";
// readPlayerCharacter for the one-shot initial draw (useState initialisers
// run before any hook value is available); the hook for everything after.
import { readPlayerCharacter, usePlayerCharacter } from "../_lib/playerCharacter";
import { buzzCrit, buzzDeflect, buzzHit, buzzHurt, buzzVictory } from "../_lib/feedback";
import { attackPose, MAX_ATTACK_TIER, ONE_SHOT_MS, type SpriteState } from "../_lib/sprites";
import { projectileFor } from "../_lib/projectiles";
import { useQuestionClock } from "../_lib/useQuestionClock";
import FighterSprite from "./FighterSprite";
import BattleHpStrip from "./BattleHpStrip";
import CountdownBar from "./CountdownBar";
import ProjectileShot from "./ProjectileShot";
import LoadingScene from "./LoadingScene";
import QuizOptions from "./QuizOptions";
import BattleResult from "./BattleResult";

// The fighters' visual scale lives in CSS (.hanko-fighter-slot in
// globals.css) rather than here, because it needs a media query: 250px
// sprites don't fit beside the card below ~1024px.

// Kahoot-style countdown per question. 10s, not Kahoot's typical faster pace
// — this tests vocabulary recall (read the word, know the meaning), not
// general-knowledge reflexes, and needs real thinking room. Divided into
// thirds for the 3-tier speed grading: fast=easy, mid=good,
// barely-in-time=hard — "Hard" genuinely means "you got it right but it was
// a struggle" in real SM-2 terms, which is exactly what a last-second
// correct answer under a timer is.
const QUESTION_TIME_LIMIT_MS = 10_000;
const EASY_CUTOFF_MS = QUESTION_TIME_LIMIT_MS / 3;
const GOOD_CUTOFF_MS = (QUESTION_TIME_LIMIT_MS * 2) / 3;

// How long the "CRIT!"/"TIME UP!" banner stays up. Only the banner — the
// sprites return to idle off their own `animationend`, so nothing here gates
// either the animation or the next question (the fight advances immediately
// and the hit plays over the already-interactive next card).
const FLAG_HOLD_MS = 900;

// Long enough for the monster's death clip (500ms in FighterSprite) to play
// AND be looked at before the next one pops in. The fight is never interrupted
// by a screen — a defeated monster is just replaced — so this pause is the
// only moment a kill gets to register, and 700ms was over before the corpse
// had finished falling. Nothing is blocked during it: the next question is
// already on screen and answerable, so a longer beat costs no playing time.
const MONSTER_SPAWN_DELAY_MS = 1200;

// Flight time for a ranged attack (see projectiles.ts). Short enough that the
// hit still reads as one action with the swing that threw it, long enough to
// see the thing cross the card. The target's flinch, its damage number and the
// buzz are all held until impact, so the arrow visibly causes them rather than
// arriving after the fact.
const PROJECTILE_FLIGHT_MS = 260;

// Nothing leaves the archer's hands until the archer has finished throwing it.
// The launch waits out the full attack clip, so the release reads as the cause
// of the shot rather than something happening alongside it. ONE_SHOT_MS is the
// same constant FighterSprite runs the clip on — see sprites.ts.
const PROJECTILE_LAUNCH_MS = ONE_SHOT_MS;

// How long a corpse stays up after a RANGED kill. Shorter than the melee
// figure because the wind-up and the flight have already held the moment for
// three quarters of a second; 700ms still covers the 500ms death clip with a
// beat to see it. Without this, a ranged kill sat on screen for nearly two
// seconds — and every one of those milliseconds is a window where an answer
// lands on a monster that is already dead and the damage goes nowhere.
const RANGED_SPAWN_DELAY_MS = 700;

type Flag = "crit" | "evaded" | "armor" | "timeout" | "victory" | null;

// How hard the swing looks, from how many you've got right in a row. The
// thresholds are the ones the fight already runs on rather than new numbers
// invented for the animation: past STREAK_BONUS_THRESHOLD the crit and evade
// bonuses are live, and at ARMOR_STREAK_INTERVAL you're earning armour. So the
// heavier clip appears exactly when the player has actually become harder to
// stop, and drops back to the plain swing the moment a wrong answer resets the
// streak to zero.
function streakTier(streak: number): number {
  if (streak >= ARMOR_STREAK_INTERVAL) return 2;
  if (streak > STREAK_BONUS_THRESHOLD) return 1;
  return 0;
}

function ratingForElapsed(elapsedMs: number): Rating {
  if (elapsedMs < EASY_CUTOFF_MS) return "easy";
  if (elapsedMs < GOOD_CUTOFF_MS) return "good";
  return "hard";
}

export default function BattleArena() {
  const params = useSearchParams();
  const deckId = params.get("deck");

  // ?mode=free — practice any card regardless of due date, logged as a drill
  // so nothing gets rescheduled. Reached from the mode chooser or from the
  // "nothing due" empty state, so wanting to practise is never a dead end.
  const freeMode = params.get("mode") === "free";

  const { queue, card, reviewedCount, error, loadError, rate, undo } =
    usePracticeSession(deckId, freeMode ? "free" : "due");

  // Fetched once on mount, not per-question: this is what replaced the old
  // per-question Jisho round-trip. RLS scopes it to the signed-in user, same
  // as every other query in this app.
  const [allWords, setAllWords] = useState<OwnWord[] | null>(null);
  useEffect(() => {
    let cancelled = false;
    supabase
      .from("words")
      .select("id, term, reading, meaning, meaning_mn")
      .eq("deleted", false)
      .then(({ data }) => {
        if (!cancelled) setAllWords((data as OwnWord[]) ?? []);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const [events, setEvents] = useState<BattleEvent[]>([]);
  const [monsterStartIndex, setMonsterStartIndex] = useState(0);
  // Read before the monster is drawn: pickMonster refuses to spawn whichever
  // character the player is using, now that three of the roster are on both
  // lists.
  const playerSlug = usePlayerCharacter();
  const [monster, setMonster] = useState(() => pickMonster(readPlayerCharacter()));

  // Counts answers whose review_card() RPC hasn't come back yet. Needed
  // because usePracticeSession removes the answered card from the queue
  // *optimistically* but only re-queues a still-learning card once the RPC
  // resolves. Answering the last card in the queue with "again" therefore
  // leaves the queue momentarily empty — without this guard the arena would
  // flash the victory/cleared screen for a few hundred milliseconds before
  // the card came back.
  const [pendingAnswers, setPendingAnswers] = useState(0);

  // The slugs, not a tally: the result screen lays the actual corpses out, so
  // it needs to know which characters they were. Order is kill order.
  const [defeatedMonsters, setDefeatedMonsters] = useState<string[]>([]);
  const monstersDefeated = defeatedMonsters.length;

  const [playerPose, setPlayerPose] = useState<SpriteState>("idle");
  const [monsterPose, setMonsterPose] = useState<SpriteState>("idle");
  const [lastFlag, setLastFlag] = useState<Flag>(null);
  // The word just answered, shown briefly with its reading. The whole point
  // of a vocabulary quiz is learning the word, and answering by meaning alone
  // never surfaces how it's actually pronounced — so the yomikata is shown
  // after the fact, when knowing it can't give the answer away.
  const [lastAnswer, setLastAnswer] = useState<{
    term: string;
    reading: string | null;
    correct: boolean;
  } | null>(null);

  // Floating damage number. `id` increments every hit so the element is
  // re-keyed and the rise/fade animation replays even when two identical
  // numbers land back to back.
  const [damagePopup, setDamagePopup] = useState<{
    id: number;
    amount: number;
    target: "player" | "monster";
    crit: boolean;
  } | null>(null);
  // Bumped only when the player actually loses HP, so the arena shakes for
  // damage taken rather than for every answer.
  const [shakeId, setShakeId] = useState(0);

  const [paused, setPaused] = useState(false);
  // Set when a question is paused, cleared when the next one arrives. A paused
  // question can't earn the fastest speed tier — the clock stops, so "answered
  // in under 3.3 seconds" would otherwise be claimable after unlimited
  // thinking time, and that tier feeds a real SM-2 rating.
  const pausedThisQuestion = useRef(false);

  const animationTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const impactTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const launchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // True from the moment a ranged attack is thrown until it connects. Three
  // things have to wait for it, and all three looked wrong when they didn't:
  // the target's flinch, the death pose (a monster that collapsed while the
  // arrow was still being nocked), and the replacement monster's spawn timer.
  const [impactPending, setImpactPending] = useState(false);
  const postImpactSpawnMs = useRef(MONSTER_SPAWN_DELAY_MS);

  // The shot currently crossing the stage, if any. `id` increments per shot so
  // the element is re-keyed and its CSS flight replays even when the same
  // character fires the same ammunition twice in a row.
  const [shot, setShot] = useState<{
    id: number;
    slug: string;
    state: SpriteState;
    toward: "right" | "left";
  } | null>(null);

  // Mirrors `events`/`monsterStartIndex`, updated synchronously at every
  // mutation site (handlePick, resolveAnswer, handleUndo, handleContinue).
  // resolveAnswer reads from these, never from the `events`/`monsterStartIndex`
  // state variables directly. Reason: resolveAnswer can be invoked from a
  // setTimeout closure (the question countdown) set up in an earlier render.
  // If the player hits Undo while that timer is still ticking — genuinely
  // reachable, the undo button has no "only when no question is active"
  // guard — the closure's captured `events` would be stale by the time the
  // timeout fires, so `deriveBattleState` would compute streak/armor from a
  // pre-undo array that no longer matches reality. Refs sidestep this: they
  // are always read fresh, regardless of which render's closure is calling.
  const eventsRef = useRef<BattleEvent[]>([]);
  const monsterStartIndexRef = useRef(0);

  // Guards against the countdown firing AFTER the player has already picked
  // (or vice versa) — both paths resolve the same question, and only one may
  // win. A ref, not state: the timeout callback closes over whatever this
  // was at effect-setup time, so a React state value here would risk acting
  // on a stale read; a ref is always read fresh.
  const answered = useRef(false);

  // buildQuiz is now pure and synchronous (see quiz.ts's revision note), so
  // this only recomputes when `card` or `allWords` actually change — not on
  // every unrelated re-render (e.g. a pose timer firing), which matters
  // because it shuffles: recomputing on every render would re-shuffle the
  // options mid-question.
  const quiz = useMemo<QuizOption[] | null>(() => {
    if (!card || !allWords) return null;
    return buildQuiz(card, allWords);
  }, [card, allWords]);

  // Derived before the timer effect below on purpose: that effect has to gate
  // on `outcome`, and a `const` can't be referenced in a dependency array
  // declared above it.
  const battleState = deriveBattleState(events, monsterStartIndex);
  const queueEmpty =
    queue !== null && !card && events.length > 0 && pendingAnswers === 0;
  const outcome = battleOutcome(battleState, queueEmpty);

  // Unique per question *presentation*, not per card: a card requeued by the
  // learning steps comes back with the same card_id, so keying the clock on
  // that alone would leave it stuck at zero when the card reappears.
  const questionKey = `${card?.card_id ?? ""}:${events.length}`;

  // Gated on `outcome === "ongoing"`: without it the countdown would keep
  // running underneath the result screen, and reading that screen for ten
  // seconds would silently auto-answer the next card as a miss. It also covers
  // the reverse — a fresh monster restarts the clock even though the current
  // card never changed.
  const { remainingMs, elapsedMs } = useQuestionClock({
    durationMs: QUESTION_TIME_LIMIT_MS,
    resetKey: questionKey,
    running: !!card && !!quiz && outcome === "ongoing" && !paused,
    onExpire: () => {
      if (answered.current) return; // already resolved by a pick right at the buzzer
      answered.current = true;
      resolveAnswer("again", true);
    },
  });

  // Refs only — no state, so this can't cascade a render.
  useEffect(() => {
    answered.current = false;
    pausedThisQuestion.current = false;
  }, [questionKey]);

  useEffect(() => {
    return () => {
      if (animationTimer.current) clearTimeout(animationTimer.current);
      if (impactTimer.current) clearTimeout(impactTimer.current);
      if (launchTimer.current) clearTimeout(launchTimer.current);
    };
  }, []);

  // A defeated monster is replaced in place rather than ending the session on
  // an interstitial screen with a "continue" button — that broke the rhythm
  // every few questions. Only a player defeat or an exhausted queue stops the
  // run now; `outcome !== "ongoing"` defers to the result screen in those
  // cases. Advancing monsterStartIndex is what refills the monster's HP (see
  // deriveBattleState), which also clears `monsterDefeated` and stops this
  // effect from re-firing.
  useEffect(() => {
    // `impactPending` holds this back until a ranged killing blow has actually
    // connected. Without it the replacement's timer started the moment the
    // arrow was loosed, so the corpse was swept away before the death clip
    // had finished playing.
    if (!battleState.monsterDefeated || outcome !== "ongoing" || impactPending) return;
    const id = setTimeout(() => {
      monsterStartIndexRef.current = eventsRef.current.length;
      setMonsterStartIndex(monsterStartIndexRef.current);
      // Recorded before the replacement is picked — `monster` here is still
      // the one that just died.
      setDefeatedMonsters((prev) => [...prev, monster]);
      setMonster(pickMonster(playerSlug));
      setPlayerPose("idle");
      setMonsterPose("idle");
    }, postImpactSpawnMs.current);
    return () => clearTimeout(id);
    // `monster` is deliberately a dependency: it's the slug being buried, and
    // reading a stale one would file the wrong corpse. Re-running when it
    // changes is harmless — advancing monsterStartIndex has already cleared
    // monsterDefeated by then, so the guard above returns immediately.
  }, [battleState.monsterDefeated, outcome, monster, impactPending, playerSlug]);

  // Deliberately NOT gated on the hit animation: the next question is shown
  // the moment it exists. buildQuiz is synchronous, so `quiz` and `card` are
  // always from the same render — there is no window where a stale question
  // could be displayed for the wrong card.
  const showingQuestion = outcome === "ongoing" && quiz !== null;

  // Runs the target's reaction now for a melee hit, or when the projectile
  // arrives for a ranged one. Only the *reaction* is delayed — the event is
  // appended immediately, so the queue advances and the next question is
  // answerable while the arrow is still in the air. The HP bar therefore drops
  // a quarter-second before the sprite flinches; that's the honest trade for
  // never making the player wait on an animation, and at 260ms the two read as
  // one beat.
  function onImpact(ranged: boolean, react: () => void) {
    if (impactTimer.current) clearTimeout(impactTimer.current);
    if (!ranged) {
      // Clears any impact still pending from a previous answer: the next
      // question is live while a shot is in the air, so a fast player can
      // genuinely answer again before the last arrow has landed.
      setImpactPending(false);
      react();
      return;
    }
    setImpactPending(true);
    impactTimer.current = setTimeout(() => {
      setImpactPending(false);
      react();
    }, PROJECTILE_LAUNCH_MS + PROJECTILE_FLIGHT_MS);
  }

  // Mounts the projectile once the throw is finished, rather than mounting it
  // now with a CSS animation-delay: parked at the thrower's feet for half a
  // second, a magic orb looks like it is waiting for a bus.
  function launch(slug: string, state: SpriteState, toward: "right" | "left") {
    if (launchTimer.current) clearTimeout(launchTimer.current);
    launchTimer.current = setTimeout(() => {
      setShot({ id: Date.now(), slug, state, toward });
    }, PROJECTILE_LAUNCH_MS);
  }

  // Shared by both a real pick and an auto-resolved timeout — the only
  // difference is `timedOut`, which flows through as a flag for the UI, not
  // a different rating or a different consequence to the scheduler.
  function resolveAnswer(rating: Rating, timedOut: boolean) {
    // Read from the refs, not the `events`/`monsterStartIndex` state
    // variables — see the refs' own comment above for why this matters when
    // called from the countdown's timeout closure.
    const stateBefore = deriveBattleState(eventsRef.current, monsterStartIndexRef.current);
    const event = rollEvent(rating, stateBefore, timedOut);

    eventsRef.current = [...eventsRef.current, event];
    setEvents(eventsRef.current);

    // The fight as of this answer. Derived from the event just appended, not
    // read from `battleState` — that's this render's value, one answer behind,
    // so it would show the streak and the monster's health as they were
    // *before* the blow that just landed.
    const stateAfter = deriveBattleState(
      eventsRef.current,
      monsterStartIndexRef.current
    );
    const killed = stateAfter.monsterDefeated;

    const correct = rating !== "again";
    if (card) {
      setLastAnswer({ term: card.term, reading: card.reading, correct });
    }
    if (correct) {
      // The swing escalates with the streak, and a crit always lands the
      // heaviest clip on the sheet. attackPose() resolves both against the
      // real sprite metadata rather than naming a pose and hoping: asking the
      // Priest (attack01 only) for attack02 fell through FighterSprite's
      // missing-pose guard to `idle`, so a Priest crit played no attack at all.
      const pose = attackPose(
        playerSlug,
        event.crit ? MAX_ATTACK_TIER : streakTier(stateAfter.streak)
      );
      setPlayerPose(pose);
      // A kill outranks a crit: the banner should say the monster went down,
      // not that the hit was strong.
      setLastFlag(killed ? "victory" : event.crit ? "crit" : null);

      // Ranged characters throw something first and connect when it lands.
      const ranged = projectileFor(playerSlug, pose) !== null;
      postImpactSpawnMs.current = ranged ? RANGED_SPAWN_DELAY_MS : MONSTER_SPAWN_DELAY_MS;
      if (ranged) launch(playerSlug, pose, "right");
      onImpact(ranged, () => {
        setMonsterPose("hurt");
        setDamagePopup({
          id: Date.now(),
          amount: event.damage,
          target: "monster",
          crit: event.crit,
        });
        if (killed) buzzVictory();
        else if (event.crit) buzzCrit();
        else buzzHit();
      });
    } else {
      setMonsterPose("attack01");
      setLastFlag(timedOut ? "timeout" : event.armorConsumed ? "armor" : event.evaded ? "evaded" : null);

      // The counter-attack travels too, for the monsters that shoot: the
      // skeleton archer's arrow, Demon_B's, the necromancer's and warlock's
      // bolts. Same flight, mirrored — it crosses the card right to left.
      const ranged = projectileFor(monster, "attack01") !== null;
      if (ranged) launch(monster, "attack01", "left");
      onImpact(ranged, () => {
        setPlayerPose(event.armorConsumed || event.evaded ? "idle" : "hurt");
        // A blocked or evaded hit costs nothing, so it gets a light tick and
        // no shake — the feedback should match what actually happened rather
        // than punishing a save as if it were a hit.
        if (event.damage > 0) {
          setDamagePopup({
            id: Date.now(),
            amount: event.damage,
            target: "player",
            crit: false,
          });
          setShakeId((n) => n + 1);
          buzzHurt();
        } else {
          buzzDeflect();
        }
      });
    }

    // Fire-and-forget for the UI's purposes: review_card() already commits
    // server-side in one transaction, same reasoning as PracticeSession's own
    // rate(). A timeout still sends a real rating — the player didn't recall
    // it in time, which is an honest `again`, not a no-op. The counter is
    // only so the arena can tell "queue is empty" apart from "queue is
    // briefly empty while a still-learning card is on its way back".
    setPendingAnswers((n) => n + 1);
    void rate(rating).finally(() => setPendingAnswers((n) => Math.max(0, n - 1)));

    // Only the text banner is on a timer now. Each sprite returns to idle off
    // its own `animationend` (see the onOneShotEnd handlers below), so a clip
    // is never cut short or left frozen on its last frame waiting for a timer
    // that doesn't match its real duration.
    if (animationTimer.current) clearTimeout(animationTimer.current);
    animationTimer.current = setTimeout(
      () => {
        setLastFlag(null);
        setLastAnswer(null);
        setDamagePopup(null);
        setShot(null);
      },
      // A kill's banner stays up until the replacement monster spawns, so the
      // "it's dead" beat and the "here's the next one" beat don't overlap.
      killed ? MONSTER_SPAWN_DELAY_MS : FLAG_HOLD_MS
    );
  }

  function handlePick(option: QuizOption) {
    // `answered.current` is the only guard needed against a double-answer:
    // it's set here and reset by the per-question effect when the next card
    // arrives, so the brief window between the two is covered without
    // disabling the buttons (which would defeat the instant-advance).
    if (!card || !quiz || answered.current) return;
    answered.current = true;

    let rating: Rating = option.correct ? ratingForElapsed(elapsedMs()) : "again";
    // The clock stops while paused, so without this the fastest tier — which
    // becomes a real "easy" for SM-2 — would be claimable after unlimited
    // thinking. "Good" is the honest ceiling for a question you stopped.
    if (rating === "easy" && pausedThisQuestion.current) rating = "good";
    resolveAnswer(rating, false);
  }

  function handleUndo() {
    if (eventsRef.current.length === 0) return;
    if (impactTimer.current) clearTimeout(impactTimer.current);
    if (launchTimer.current) clearTimeout(launchTimer.current);
    setImpactPending(false);
    setShot(null);
    eventsRef.current = eventsRef.current.slice(0, -1);
    setEvents(eventsRef.current);
    void undo();
  }

  // Start the fight over after a defeat. Clearing `events` is what refills
  // BOTH health bars: player HP is derived from every event in the session
  // and monster HP from those since monsterStartIndex, so emptying the array
  // and resetting the index puts both back to full.
  //
  // This throws away only the *battle* record. The reviews themselves already
  // committed server-side, card by card, as they were answered — a defeat
  // doesn't and shouldn't un-review the words you got through, so the queue
  // deliberately picks up where it left off rather than restarting.
  function togglePause() {
    setPaused((p) => {
      if (!p) pausedThisQuestion.current = true;
      return !p;
    });
  }

  function handleRetry() {
    setPaused(false);
    if (impactTimer.current) clearTimeout(impactTimer.current);
    if (launchTimer.current) clearTimeout(launchTimer.current);
    setImpactPending(false);
    eventsRef.current = [];
    setEvents([]);
    monsterStartIndexRef.current = 0;
    setMonsterStartIndex(0);
    setMonster(pickMonster(playerSlug));
    setDefeatedMonsters([]);
    setPlayerPose("idle");
    setMonsterPose("idle");
    setLastFlag(null);
    setLastAnswer(null);
    setDamagePopup(null);
    setShot(null);
  }

  if (queue === null || allWords === null) {
    return <LoadingScene label={T.loadingWords} />;
  }

  if (allWords.length < MIN_WORDS_FOR_BATTLE) {
    return (
      <div className="mx-auto max-w-md p-8 text-center">
        <div className="rounded-control border border-dashed border-line bg-white p-10 text-ink-soft">
          {T.notEnoughWordsBattle}
        </div>
      </div>
    );
  }

  if (!card && events.length === 0) {
    return (
      <div className="mx-auto flex max-w-md flex-col items-center gap-3 p-8 text-center">
        {loadError ? (
          // A failed review_queue() call, NOT an ordinary quiet queue — these
          // used to render identically, which made a real outage look like a
          // normal day with nothing due.
          <div className="w-full rounded-control border border-red-200 bg-red-50 p-6 text-sm text-red-700">
            <p className="font-medium">{T.queueLoadFailed}</p>
            <p className="mt-2 text-xs opacity-80">{loadError}</p>
          </div>
        ) : (
          <>
            <div className="w-full rounded-control border border-dashed border-line bg-white p-10 text-ink-soft">
              <p>{T.noWordsDueBattle}</p>
              <p className="mt-2 text-xs text-ink-mute">{T.noWordsDueBattleHint}</p>
            </div>
            {/* Not a dead end: wanting to practise when nothing is scheduled
                is a completely reasonable thing to want, so offer it right
                here rather than making the user go hunting for it. Only shown
                when this isn't already a free session — otherwise it would
                link to the page you're on. */}
            {!freeMode && (
              <Link
                href="/decks/review/battle?mode=free"
                className="w-full hk-btn hk-btn-primary px-4 py-3 text-sm"
              >
                {T.freePracticeCta}
              </Link>
            )}
            <Link
              href="/decks"
              className="text-sm font-medium text-ink underline"
            >
              {T.backToDecks}
            </Link>
          </>
        )}
      </div>
    );
  }

  if (outcome !== "ongoing") {
    return (
      <BattleResult
        outcome={outcome}
        reviewedCount={reviewedCount}
        defeatedMonsters={defeatedMonsters}
        // The raw event log, so the result screen can derive its own summary
        // (accuracy, peak streak) instead of BattleArena carrying extra state
        // that only matters after the fight is over.
        events={events}
        monster={monster}
        monsterDown={battleState.monsterDefeated}
        onRetry={outcome === "defeat" ? handleRetry : undefined}
      />
    );
  }

  // Nobody falls over until the shot that killed them has landed. HP is
  // derived from `events` and so drops the instant the answer is scored, but a
  // fighter collapsing while the arrow is still in the air is the one part of
  // that head start you'd actually notice.
  const playerDisplayPose =
    battleState.playerDefeated && !impactPending ? "death" : playerPose;
  const monsterDisplayPose =
    battleState.monsterDefeated && !impactPending ? "death" : monsterPose;

  return (
    <div className="mx-auto flex min-h-[calc(100vh-8rem)] max-w-5xl flex-col justify-center px-4 py-6 sm:py-8 xl:max-w-7xl 2xl:max-w-[1400px]">
      <div className="hk-arena relative flex flex-col gap-4 p-4 sm:p-6">
      {/* Leaving and pausing on the left, session controls on the right. There
          was no way out of a fight but the browser's back button, and no way
          to stop the ten-second clock at all. */}
      <div className="flex items-center justify-between gap-2 text-xs">
        <div className="flex items-center gap-1">
          <Link
            href="/decks/review"
            className="flex items-center gap-1 rounded-control px-2 py-1 font-medium text-paper/60 transition hover:bg-white/10 hover:text-paper"
          >
            <ArrowLeft size={13} /> {T.exitBattle}
          </Link>
          <button
            onClick={togglePause}
            className="flex items-center gap-1 rounded-control px-2 py-1 font-medium text-paper/60 transition hover:bg-white/10 hover:text-paper"
          >
            {paused ? <Play size={13} /> : <Pause size={13} />}
            {paused ? T.resumeBattle : T.pauseBattle}
          </button>
        </div>
        <div className="flex items-center gap-2">
          {/* The kill count only existed on the result screen, so a fight you
              never finished never showed what you'd beaten. */}
          {monstersDefeated > 0 && (
            <span className="flex items-center gap-1 rounded-full bg-white/10 px-2 py-1 font-medium text-paper/80">
              <Skull size={12} /> {T.killCount(monstersDefeated)}
            </span>
          )}
          {battleState.armorCharges > 0 && (
            <span className="rounded-full bg-sky-400/15 px-2 py-1 font-medium text-sky-200 ring-1 ring-sky-400/30">
              🛡️ {T.armorGainedLabel}
            </span>
          )}
          <button
            onClick={handleUndo}
            disabled={events.length === 0}
            title={T.undoTitle}
            className="flex items-center gap-1 rounded-control px-2 py-1 font-medium text-paper/60 transition hover:bg-white/10 hover:text-paper disabled:opacity-30 disabled:hover:bg-transparent"
          >
            <Undo2 size={13} /> {T.undo}
          </button>
        </div>
      </div>

      {error && (
        <p className="rounded-control bg-red-500/15 px-3 py-2 text-center text-xs text-red-200 ring-1 ring-red-400/30">
          {T.saveFailed}
        </p>
      )}

      {/* Stated plainly rather than left implicit: in free mode the answers
          genuinely don't count toward scheduling or streaks, and a player who
          assumed otherwise would be doing work they think is "counting" when
          it isn't. */}
      {freeMode && (
        <p className="rounded-control bg-sky-400/10 px-3 py-2 text-center text-xs text-sky-200 ring-1 ring-sky-400/25">
          {T.freePracticeBanner}
        </p>
      )}

      <BattleHpStrip
        playerHp={battleState.playerHp}
        monsterHp={battleState.monsterHp}
        maxHp={PLAYER_MAX_HP}
      />

      {/* Fixed-height, always rendered: an element that appears and vanishes
          between questions would shove everything below it up and down. */}
      <div className="flex h-8 items-center justify-center gap-3">
        {lastAnswer && (
          <span
            className={`text-base font-semibold ${
              lastAnswer.correct ? "text-emerald-600" : "text-red-600"
            }`}
          >
            {lastAnswer.term}
            {/* Only when it adds something: a kana-only word's reading is
                identical to the term, and echoing it twice reads as a bug. */}
            {lastAnswer.reading && lastAnswer.reading !== lastAnswer.term && (
              <span className="ml-2 font-normal opacity-80">
                {lastAnswer.reading}
              </span>
            )}
          </span>
        )}
        {lastFlag && (
          <span
            className={`text-sm font-bold tracking-wide ${
              lastFlag === "victory" ? "text-emerald-500" : "text-amber-600"
            }`}
          >
            {lastFlag === "victory" && T.victoryFlag}
            {lastFlag === "crit" && T.critLabel}
            {lastFlag === "evaded" && T.evadedLabel}
            {lastFlag === "armor" && T.armorBlockedLabel}
            {lastFlag === "timeout" && T.timeUpLabel}
          </span>
        )}
      </div>

      {/* Arena. `flex-wrap` + explicit ordering gives two layouts from one set
          of elements (no duplicated sprites): below lg the two fighters share
          the first line facing each other with the card wrapped beneath them;
          at lg the row stops wrapping and they flank the card.
          `lg:h-[420px]` fixes the row's height so the fighters sit at a
          constant vertical position — combined with the fixed-height quiz
          options, nothing in this arena can move between questions. */}
      <div
        key={`shake-${shakeId}`}
        className={`relative flex flex-wrap items-center justify-center gap-3 lg:h-[420px] lg:flex-nowrap lg:gap-4 xl:h-[460px] 2xl:h-[520px] 2xl:gap-5 ${
          shakeId > 0 ? "hanko-shake" : ""
        }`}
      >
        {/* Rendered in the row, not in either fighter's slot: it belongs to
            neither, and it has to be able to travel the whole width. Re-keyed
            per shot so its CSS flight restarts every time. */}
        {shot && (
          <ProjectileShot
            key={shot.id}
            slug={shot.slug}
            state={shot.state}
            toward={shot.toward}
            durationMs={PROJECTILE_FLIGHT_MS}
          />
        )}

        <div className="hanko-fighter-slot relative order-1 flex shrink-0 items-center justify-center">
          <FighterSprite
            slug={playerSlug}
            state={playerDisplayPose}
            onOneShotEnd={() => setPlayerPose("idle")}
          />
          {damagePopup?.target === "player" && (
            <span
              key={damagePopup.id}
              className="hanko-float-up pointer-events-none absolute left-1/2 top-4 text-2xl font-extrabold text-red-500 drop-shadow"
            >
              -{damagePopup.amount}
            </span>
          )}
        </div>

        <div
          key={monster}
          className="hanko-fighter-slot hanko-spawn relative order-2 flex shrink-0 items-center justify-center lg:order-3"
        >
          <FighterSprite
            slug={monster}
            state={monsterDisplayPose}
            flip
            onOneShotEnd={() => setMonsterPose("idle")}
          />
          {damagePopup?.target === "monster" && (
            <span
              key={damagePopup.id}
              className={`hanko-float-up pointer-events-none absolute left-1/2 top-4 font-extrabold drop-shadow ${
                damagePopup.crit
                  ? "text-3xl text-amber-400"
                  : "text-2xl text-emerald-400"
              }`}
            >
              -{damagePopup.amount}
            </span>
          )}
        </div>

        {/* Explicit widths, not flex-1: the sprite slots are sized to fit
            AROUND these numbers (see globals.css), so growing a fighter can
            never come out of the question card's width.

            `relative z-10` puts the card above both slots. The slots are
            positioned, so without it they'd paint over the card — and the
            fighters now deliberately overhang their slots during attack and
            death clips. A sword crossing the card's edge should pass behind
            the parchment, not across the answer text. */}
        <div className="relative z-10 order-3 flex w-full shrink-0 items-center justify-center lg:order-2 lg:h-full lg:w-[430px] xl:w-[490px] 2xl:w-[540px]">
          {showingQuestion && quiz ? (
            <div className="hanko-parchment flex w-full flex-col gap-4 px-6 py-8 text-center sm:px-8 xl:gap-5 xl:px-10 xl:py-10">
              <div className="text-4xl font-bold tracking-tight text-ink xl:text-5xl 2xl:text-6xl">
                {card?.term}
              </div>
              <CountdownBar
                durationMs={QUESTION_TIME_LIMIT_MS}
                remainingMs={remainingMs}
                paused={paused}
              />
              <QuizOptions options={quiz} disabled={paused} onPick={handlePick} />
            </div>
          ) : (
            <div className="flex min-h-[340px] w-full items-center justify-center rounded-card bg-white/5 px-8 py-10 text-sm text-paper/50">
              {T.loadingQuiz}
            </div>
          )}
        </div>
      </div>

      {/* Covers the whole stage rather than just the card: the point of a
          pause is that the question is not readable while the clock is
          stopped, so leaving the term and the four options on screen would
          make it a free thinking window instead. */}
      {paused && (
        <div className="absolute inset-0 z-20 flex flex-col items-center justify-center gap-4 rounded-card bg-[#171d25]/85 px-6 text-center backdrop-blur-sm">
          <Pause size={30} className="text-paper/70" />
          <h2 className="text-2xl font-bold tracking-tight text-paper">
            {T.pausedTitle}
          </h2>
          <p className="max-w-xs text-sm leading-relaxed text-paper/55">
            {T.pausedDesc}
          </p>
          <div className="flex flex-col gap-2 sm:flex-row">
            <button
              onClick={togglePause}
              className="hk-btn hk-btn-primary px-5 py-2.5 text-sm"
            >
              <Play size={15} />
              {T.resumeBattle}
            </button>
            <Link
              href="/decks/review"
              className="hk-btn border border-white/15 bg-white/5 px-5 py-2.5 text-sm text-paper hover:bg-white/10"
            >
              <ArrowLeft size={15} />
              {T.exitBattle}
            </Link>
          </div>
        </div>
      )}
      </div>
    </div>
  );
}
