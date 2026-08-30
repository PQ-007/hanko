import Link from "next/link";
import { RotateCcw, X } from "lucide-react";
import type { BattleEvent, BattleOutcome } from "../_lib/damage";
import { PLAYER_CHARACTER } from "../_lib/monsters";
import { T } from "../../../_lib/strings";
import FighterSprite from "./FighterSprite";

// Only two terminal states remain. Beating a monster no longer stops the
// session — the next one spawns in the arena (see BattleArena's auto-spawn
// effect), so this screen appears when the player is defeated or the queue is
// finished, never between opponents.
//
// It renders on the same dark .hk-arena stage the fight itself uses, rather
// than dropping the player onto the app's paper background. The fight and its
// aftermath are one place; a centred column of text on paper read as a
// different screen that had merely been navigated to.

// Longest run of consecutive correct answers in the session. Derived here
// rather than tracked in BattleArena because deriveBattleState only carries
// the *current* streak (it's what crit/evade/armor are rolled from) — the
// peak only becomes interesting once the fight is over.
// Past this the corpses stop being a scene and start being a spreadsheet; the
// rest are summarised as "+N".
const MAX_TROPHIES = 8;

// One body gets the stage to itself; a few still read as individuals; past
// that they're a pile and are sized to fit four across the card.
function trophySlot(count: number): string {
  if (count === 1) return "hanko-fighter-slot-lg";
  if (count <= 3) return "hanko-fighter-slot-sm";
  return "hanko-fighter-slot-trophy";
}

function bestStreakOf(events: BattleEvent[]): number {
  let best = 0;
  let run = 0;
  for (const e of events) {
    if (e.rating === "again") run = 0;
    else best = Math.max(best, ++run);
  }
  return best;
}

function StatTile({ label, value }: { label: string; value: string }) {
  return (
    // flex-col-reverse, not order utilities: inside a <dl> the <dt> has to
    // come first in source order, but the number reads better above its label.
    <div className="flex flex-col-reverse rounded-control bg-white/5 px-3 py-3 text-center ring-1 ring-white/10">
      <dt className="mt-0.5 text-[11px] leading-tight text-paper/55">{label}</dt>
      <dd className="text-2xl font-bold tabular-nums text-paper">{value}</dd>
    </div>
  );
}

export default function BattleResult({
  outcome,
  reviewedCount,
  defeatedMonsters,
  events,
  monster,
  monsterDown,
  onRetry,
}: {
  outcome: Exclude<BattleOutcome, "ongoing">;
  reviewedCount: number;
  /** Slugs of the monsters killed this run, in kill order. */
  defeatedMonsters: string[];
  events: BattleEvent[];
  monster: string;
  // True only when the run ended on the same blow that killed the monster —
  // then the corpse on screen is the real state. Every other "cleared" ends
  // with a monster still standing, and posing it dead would be a lie.
  monsterDown: boolean;
  // Retry resets the fight in place rather than navigating. It used to be a
  // <Link> to /decks/review/battle — the route the player is already on — so
  // Next's client-side navigation matched the current URL, never remounted
  // the arena, and the defeat screen just sat there. In-place reset also
  // keeps ?mode=free, which that link silently dropped.
  onRetry?: () => void;
}) {
  const defeated = outcome === "defeat";
  // The monster on screen when the run ended counts too, if the run ended on
  // the blow that killed it: BattleArena only files a corpse once the
  // replacement spawns, which never happens when the fight stops there.
  const kills = monsterDown ? [...defeatedMonsters, monster] : defeatedMonsters;
  const shownKills = kills.slice(0, MAX_TROPHIES);
  // Clearing the queue having beaten nothing is a finished day; clearing it
  // over the bodies of monsters is a win, and should say so.
  // Killing anything makes the run a win, even if the player's own HP ran out
  // afterwards. `outcome` stays "defeat" — it's what puts the retry button on
  // screen — but a fight you walked away from with three corpses behind you is
  // not a loss, and shouldn't be titled like one.
  const won = kills.length > 0;
  const correct = events.filter((e) => e.rating !== "again").length;
  const crits = events.filter((e) => e.crit).length;

  return (
    <div className="mx-auto flex min-h-[calc(100vh-8rem)] max-w-3xl flex-col justify-center px-4 py-6 sm:py-8">
      <div className="hk-arena flex flex-col items-center gap-6 px-5 py-8 text-center sm:px-10 sm:py-12">
        <span
          className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] ring-1 ${
            defeated
              ? "bg-red-500/15 text-red-200 ring-red-400/30"
              : "bg-emerald-500/15 text-emerald-200 ring-emerald-400/30"
          }`}
        >
          {T.resultKicker}
        </span>

        <div className="flex flex-col gap-2">
          <h1 className="text-3xl font-extrabold tracking-tight text-paper sm:text-4xl">
            {defeated ? T.defeatTitle : won ? T.victoryTitle : T.clearedTitle}
          </h1>
          {/* Title comes from whether you won; the description from how the
              run actually ended, because the practical note (a retry does not
              un-review the words you got through) still applies to a victory
              that ended with the player face-down. */}
          <p className="mx-auto max-w-sm text-sm leading-relaxed text-paper/55">
            {defeated ? T.defeatDesc : won ? T.victoryDesc : T.clearedDesc}
          </p>
        </div>

        {/* The scene, not a summary line. Everything you killed lies here,
            each corpse playing its own death clip once on mount and then
            holding the last frame (FighterSprite's one-shots end on
            fill-mode: forwards).

            No player sprite when there are kills: a win screen is about what
            you put on the ground, and a knight standing among the bodies was
            competing with them for both space and attention. It comes back
            only for the one scene that needs it — beaten without landing a
            single kill, where the two figures ARE the story. */}
        <div className="flex flex-col items-center gap-3">
          {kills.length === 0 ? (
            <div className="flex flex-wrap items-end justify-center gap-2 sm:gap-6">
              {defeated && (
                <div className="hanko-fighter-slot-sm flex items-center justify-center">
                  <FighterSprite slug={PLAYER_CHARACTER} state="death" />
                </div>
              )}
              <div
                className={`flex items-center justify-center ${
                  defeated ? "hanko-fighter-slot-sm" : "hanko-fighter-slot-lg"
                }`}
              >
                <FighterSprite slug={monster} state="idle" flip />
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap items-end justify-center gap-2 sm:gap-3">
              {shownKills.map((slug, i) => (
                <div
                  // Index-keyed on purpose: the same monster can be drawn
                  // twice in one run, so the slug isn't unique.
                  key={`${slug}-${i}`}
                  className={`flex items-center justify-center ${trophySlot(kills.length)}`}
                >
                  <FighterSprite slug={slug} state="death" flip />
                </div>
              ))}
              {kills.length > MAX_TROPHIES && (
                <span className="self-center text-lg font-bold text-paper/60">
                  +{kills.length - MAX_TROPHIES}
                </span>
              )}
            </div>
          )}
          <p className="text-xs font-medium text-paper/50">
            {kills.length > 0
              ? T.monstersDefeated(kills.length)
              : T.noMonsterDefeated}
          </p>
        </div>

        {/* Note the two scopes, which is deliberate rather than an oversight:
            reviewedCount spans the whole visit (handleRetry does not, and must
            not, un-review words already answered — defeatDesc says so), while
            the other three come from `events`, which a retry clears.

            The kill count used to be a tile here. The scene above now states
            it in words directly under the corpses, so the tile was saying the
            same thing twice; crits landed is the stat that wasn't shown
            anywhere. */}
        <dl className="grid w-full max-w-md grid-cols-2 gap-2 sm:grid-cols-4">
          <StatTile label={T.resultWords} value={String(reviewedCount)} />
          <StatTile label={T.resultCrits} value={String(crits)} />
          <StatTile label={T.resultCorrect} value={`${correct}/${events.length}`} />
          <StatTile label={T.resultBestStreak} value={String(bestStreakOf(events))} />
        </dl>

        <div className="flex w-full max-w-md flex-col gap-2 sm:flex-row">
          {defeated && onRetry && (
            <button
              onClick={onRetry}
              className="hk-btn hk-btn-primary flex-1 px-4 py-3 text-sm"
            >
              <RotateCcw size={15} />
              {T.retryBattle}
            </button>
          )}
          {/* hk-btn-quiet is a white button — glaring beside the seal one on a
              dark stage. The secondary action is an outline here instead. */}
          <Link
            href="/decks/stats"
            className="hk-btn flex-1 border border-white/15 bg-white/5 px-4 py-3 text-sm text-paper hover:bg-white/10"
          >
            <X size={15} />
            {T.stopBattle}
          </Link>
        </div>
      </div>
    </div>
  );
}
