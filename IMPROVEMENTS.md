# Hanko — improvement plan

Written after the Монстр агнах / Давтах work landed (`a15533e`). Ordered by
what unblocks or protects the most, not by size. Each phase is independent —
you can stop after any of them and the app is in a coherent state.

Companion to `CLAUDE.md`, which stays the project brief. This file is the
"what next" list; move anything that becomes permanent truth into CLAUDE.md and
delete it from here.

---

## Ground truth — verified, do not re-derive

Checked against the working tree at `a15533e`. Trust this over memory.

- **`node --test` runs TypeScript directly on this machine** (Node v22.22.2 —
  type stripping is on by default from 22.18). Confirmed with a real
  `.test.ts` importing a `.ts` module: no loader, no build step, no
  dependency, no config.
- **The four battle logic modules import only *types***
  (`damage.ts` → `@/lib/srs`, `quiz.ts` → `_lib/types`, `projectiles.ts` →
  `./sprites`; `monsters.ts` and `sprites.ts` import nothing). Type imports are
  erased by stripping, so none of them need the `@/` path alias resolved at
  test time. They are testable exactly as they are.
- ~~`web/` has no test script and no test files.~~ It does now: `npm test` runs
  41 tests over five suites. `mobile/` has four of its own. `src/sync.test.js`
  remains the house style for the extension's dependency-free tests.
- ~~Monster Hunt is indistinguishable from classic review in `review_log`.~~
  Scored battle now sends `source='quiz'` (0018) — real scheduling, labelled.
- ~~`streakTier()` is not exported.~~ Moved into `damage.ts`, where it reads
  its own thresholds and can be tested.
- **Battle art weighs 1.2 MB** (`web/public/battle/characters`) plus 48 KB of
  projectiles. Largest JS chunk is 224 KB.

---

## Status

| | |
|---|---|
| A.1 confirm migrations | **yours** — now `0016`–`0019` |
| A.2 click-through | **yours** — checklist below |
| B.1 rating cap | **done** |
| B.2 `quiz` source | **done** — `0018`, verified on real Postgres 16 |
| C.1 web tests | **done** — 50 tests, `npm test` in `web/` |
| C.2 CLAUDE.md refresh | **done** |
| D.1 asset licensing | **yours** — nothing a code change can settle |
| D.2 `/api/lookup` throttle | **done** |
| D.3 repackage extension | **yours** |
| E PvP | **phases 1–4 done** — see `PVP.md`; unplayed, phase 5 is yours |
| F.1 battle shortcuts | **done**, and it turned up a live bug (below) |
| F.2 SRS-day streak | **done** — `0019`, both clients, parity tested |

## Phase A — Unblock (do first, both cheap)

### A.1 Confirm `0016`, `0017` and `0018` are applied

`practice_cards()` is what free practice calls. You hit *"Could not find the
function public.practice_cards"* during development; whether you have since run
the migration is not something this repo records. Paste both into the Supabase
SQL editor — they are written to be safely re-runnable, so applying an
already-applied one is a no-op.

`0018_quiz_source.sql` is new and must go on last. It was applied to a clean
Postgres 16 in sequence with every other migration, exercised (quiz reschedules,
drill and battle do not, invalid sources still rejected, replay stays
idempotent, the heatmap and the daily caps both count quiz), and then applied a
second time to confirm it is re-runnable.

**Done when:** `/decks/review` → Чөлөөт дасгал serves a card on a day with an
empty queue, and a Monster Hunt answer shows up in `review_log` as `'quiz'`
with the card's `due_at` moved.

### A.2 One real click-through

Fifteen rounds of UI work have been verified by reading, building and
measuring — never by rendering. That is the single largest source of unknown
risk in the current tree. The list below is ordered by where the reasoning was
most involved, i.e. where being wrong is most likely:

1. **Ranged timeline.** Play as Archer or Wizard. The arrow should leave at
   500 ms (after the swing finishes), land at 760 ms, and the monster should
   not flinch, show damage or fall over before it lands. A ranged kill should
   spawn the next monster ~1460 ms after impact.
2. **Landing page at exactly 1024 px and 1280 px.** The two-column split is
   sized from the narrowest viewport in each band; those two widths are where
   it is tightest.
3. **A Priest or Wizard crit.** Both have short attack chains, so these are the
   only characters that exercise `attackPose()`'s clamp. A missing pose falls
   through to `idle` and the swing silently vanishes.
4. **Pause mid-question, then answer.** The clock must resume from where it
   stopped. (The pause-specific `easy` cap is gone — `scheduleRating()` now
   caps every battle answer, so pausing needs no rule of its own.)
5. **Undo while an arrow is in flight.** Should clear the shot and the pending
   impact, not leave a frozen sprite.
6. **Keyboard in battle.** `1`-`4` and `A`-`D` pick, `U` undoes, `Esc`/`P`
   pauses — and nothing but pause/undo does anything while paused.
7. **Reduced motion** (OS setting). Sprites freeze on frame 0 and the walk-on
   snaps — acceptable — but HP, damage numbers and the queue must still work.

**Done when:** each of the six behaves, or has an issue filed with the exact
viewport/character.

---

## Phase B — Scheduling integrity (the one that gets worse with time)

**The problem.** A four-option question has a 25% floor. Guess correctly inside
3.3 s and `ratingForElapsed()` returns `easy`, which `review_card()` turns into
a real interval extension on a card you do not know. Classic review has no such
channel — you self-rate, and nobody rates a card they just failed as Amархан.

Every other gamified surface in this project is careful about this: the speed
round logs `source='drill'` precisely so pressured answers cannot touch SM-2,
and a paused battle question is already capped at `good` for exactly this
reason. Scored Monster Hunt is the one place where a guess earns real
scheduling credit.

This is worth fixing before there is a year of history rather than after.

### B.1 Cap the rating without touching the game (small)

Separate the two things `ratingForElapsed()` currently conflates: the **speed
tier**, which drives damage and should keep all three levels, and the **rating
sent to `review_card()`**, which should not include `easy` in a mode where 25%
of correct answers are luck.

In `BattleArena.tsx`:

```ts
// Damage keeps three tiers; scheduling gets at most "good".
const speedRating = ratingForElapsed(elapsedMs());
const scheduleRating: Rating = speedRating === "easy" ? "good" : speedRating;
```

`resolveAnswer` takes both — `rollEvent(speedRating, …)` for the event,
`rate(scheduleRating)` for the RPC. The existing pause cap collapses into the
same clamp rather than being a second special case.

**Cost:** nothing visible. Fast answers still crit harder and hit harder.

### B.2 Make battle answers *identifiable* (medium, recommended)

Right now you cannot measure whether B.1 was necessary, because scored battle
answers are written as `source='review'` — byte-identical to classic ones. The
data to answer the question exists (`ease_before`, `interval_before` from Phase
0.4) but there is no column that separates the two populations.

Migration `0018_quiz_source.sql`:

- Add `'quiz'` to `review_log.source`'s check constraint.
- `review_card()` currently hard-returns for any `p_source <> 'review'`. Change
  that guard to **reschedule for `'review'` and `'quiz'`**, and log-only for
  `'battle'` and `'drill'`. Keep the shape of the existing branch — this is one
  predicate, not a rewrite.
- **`review_activity()` and `due_summary()` filter `source = 'review'`.** They
  must become `source in ('review','quiz')` in the same migration, or the
  heatmap and streak silently stop counting Monster Hunt sessions the day this
  ships. This is the part that turns a good idea into a regression if missed.

Then `usePracticeSession` sends `'quiz'` for scored battle, and the question
becomes answerable with SQL:

```sql
-- lapse rate by how the card was last reviewed
select prev.source, count(*) filter (where r.rating = 'again')::numeric / count(*)
from review_log r join lateral (…) prev on true
where r.source in ('review','quiz') group by 1;
```

**Done when:** a scored battle answer appears in `review_log` as `'quiz'`, the
card's `due_at` still moves, and `/decks/stats` shows the same numbers it did
the day before.

---

## Phase C — Protect what exists

### C.1 Check in the tests that keep getting thrown away

Every round of the battle work was verified with a throwaway node script that
was then deleted. The same properties get re-derived from scratch each time,
and nothing guards them between sessions. All of it is pure functions over the
modules listed in Ground Truth, so this is transcription, not new work.

Add `"test": "node --test src/**/*.test.ts"` to `web/package.json` and write:

| File | What it pins |
|---|---|
| `_lib/damage.test.ts` | Speed-tier boundaries at 3333/6667 ms, per-tier multipliers, flat wrong-pick damage, armour grant/consume/cap, crit and evade under a stubbed `Math.random`, defeat-before-clear end-state order, and undo reproducing the prior state exactly |
| `_lib/quiz.test.ts` | Word-id (not term-string) exclusion, blank meanings never offered, `meaning_mn` → `meaning` fallback, thin-pool degradation, and a shuffle-uniformity run — the original `.sort(() => Math.random() - 0.5)` measured 36%/17%/16%/31% against a required 25% |
| `_lib/monsters.test.ts` | The shuffle bag: all 33 monsters inside 33 draws, zero back-to-back repeats across a reshuffle, and zero self-matchups when `exclude` is passed |
| `_lib/sprites.test.ts` | `attackChain` order and `attackPose` clamping (the Priest, one attack, must never resolve to something it lacks), and `critPose` = heaviest |

Move `streakTier()` out of `BattleArena.tsx` into `damage.ts` while doing
this — it is game logic sitting in a component, it already depends on that
module's thresholds, and it is untestable where it is.

**Deliberately not covered:** anything needing a DOM. There is no jsdom here and
adding one to test a sprite component is not worth it; the components stay
covered by the Phase A walkthrough.

### C.2 Refresh `CLAUDE.md`

It is now wrong in three ways that would actively mislead a future session:

- Describes the **distractor cache** and `/api/distractors` as the design.
  Both were deleted; `0016` drops the table.
- Says battle answers use **`source='battle'`** and are excluded from stats.
  Scored Monster Hunt uses `'review'` (or `'quiz'` after B.2) and *is* real
  review. The `'battle'` value is still reserved for the unbuilt PvP mode —
  that distinction needs stating, because it is exactly the kind of thing that
  gets "fixed" by someone tidying up.
- Lists **Phase 3.2 as unstarted**. Monster Hunt is built and shipped; what
  remains unbuilt is PvP specifically.

Add a one-line pointer to this file under Standing notes.

---

## Phase D — Before anything is published

Not development work, but each is a blocker rather than a nice-to-have.

- **Asset licensing.** Neither RPG pack shipped a license or readme, and there
  is now 1.2 MB of their art committed plus the projectile sheets. Fine for a
  personal project; needs confirming before this is public or monetised. Not
  something a code change can resolve.
- **`/api/lookup` is unauthenticated and unthrottled** and proxies Jisho
  (`web/src/app/api/lookup/route.ts` — no auth check, no rate limit). On a
  public URL that is an open proxy, and it is the mobile app's dictionary too.
  Cheapest real fix: an IP-keyed token bucket in the route, plus a short cache
  on the term.
- **The extension has not been repackaged** since the sync-cursor fix. The bug
  it fixes is silent, permanent row loss under clock skew, so this is worth
  more than it looks. `hanko-1.1.1.zip` exists in `web-ext-artifacts/` but has
  not been smoke-tested or uploaded.

---

## Phase E — PvP for real

**Planned in full in `PVP.md`** — surface decision (web, not Flutter), the
reuse boundary, five phases with a playable bot duel at phase 2, and the
migration sketch. The summary below is kept only as the entry point.

The placeholder on `/decks/review` is honest but inert. `CLAUDE.md` 3.2 already
holds the design worth keeping; the parts that matter:

- **Do not invoke an edge function per round.** At a 3–5 s round timer that is
  a cold-start-prone invocation every few seconds per match. An edge function
  starts the *match* and issues the round schedule; each round resolves through
  an idempotent Postgres function both clients call, first writer wins.
  Transport is one Supabase Realtime channel per match.
- **Ship the bot opponent first.** It makes the mode playable on day one and
  defers all matchmaking. Tunable reaction time and accuracy.
- **Both players are quizzed from their own decks**, so mismatched deck sizes
  stay fair.
- **Battle answers use `source='battle'`** — logged, never scheduled. Guesses
  under a 3-second timer are noise, and this is the reservation that value was
  created for.

Distractor generation, which the original plan called the unsolved problem, is
solved: `quiz.ts` builds options from the player's own library with a
`MIN_WORDS_FOR_BATTLE` floor. PvP inherits it.

**Suggested order:** bot opponent against the existing arena → match state in
Postgres → Realtime channel → matchmaking.

---

## Phase F — Small, do any time

- ~~**Keyboard shortcuts in battle.**~~ Done — and it was not the small win it
  looked like. The classic bindings live in `usePracticeSession`, which Monster
  Hunt also consumes, and its comment claimed the arena got them "by
  construction". It did, and they did not adapt: two presses of the space bar
  called `rate("good")` straight through the hook, so the card was **scheduled
  and the queue advanced while the fight never saw the answer** — no damage
  rolled, no HP moved, `events` still empty, and the `answered` guard never
  set. Shortcuts are opt-out now and the arena binds its own.
- ~~**Streak "today" comes from the device clock.**~~ Done, in both clients
  against one definition. `current_srs_day()` (0019) returns the same day key
  `review_activity()` buckets by; the web dashboard and the mobile stats screen
  both start their walk from it and fall back to the device date if the RPC is
  missing. Mobile's `currentStreak` already took `today` as a parameter, so
  only its call site was wrong. Boundary verified on real Postgres (03:59 local
  and 04:01 local are different SRS days; a 01:00 review buckets to the
  previous one, which is exactly where the device disagreed), and the two
  clients' walks are now pinned against each other case-for-case. Both clients walk back from
  `new Date()` / `DateTime.now()` rather than the server's SRS day cutoff, so
  between local midnight and `day_cutoff_hour` (up to 4 h) they can be off by
  one day. The activity data itself is correctly bucketed by `0013`; only the
  "what day is it" input is wrong. Fix is one server round trip, in both
  clients, against one definition.
- **Hero chips wrap to two rows** in the narrower landing column. Fine as a
  roster grid; one number in `.hanko-hero-chip` if you disagree.

---

## Acceptance

Whole-plan done when: free practice works (A.1), the six walkthrough items pass
(A.2), a guessed fast answer can no longer earn `easy` (B.1), `npm test` in
`web/` passes with the four suites (C.1), and `CLAUDE.md` no longer describes
the distractor cache (C.2).

Phases D, E and F are independent of that and of each other.
