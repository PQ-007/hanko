# Hanko — PvP duel plan

`Найзтайгаа тулах`. The inert "Тун удахгүй" row on `/decks/review` and in the
dashboard's mode modal, made real.

**Status: phases 1–4 are built.** `/decks/review/duel` plays a bot duel with no
network at all, and an invite-code match against a real player through
`0020_pvp.sql` + one Realtime channel. What is NOT done is phase 5 — nobody has
played it. Every balance number is a first-pass guess that survived simulation,
not an evening of real play, and the arena has been verified by building,
typechecking and 88 tests rather than by rendering. See "What is left" at the
bottom.

Companion to `CLAUDE.md` (the brief) and `IMPROVEMENTS.md` (the follow-up
list). `IMPROVEMENTS.md` Phase E called this "its own project" and it is —
hence a file of its own. Move anything that becomes permanent truth into
`CLAUDE.md` and delete it from here.

---

## Two decisions taken up front

**It ships on the web, not on Flutter.** `CLAUDE.md` 3.2 says
`mobile/lib/features/battle/`; that line predates Monster Hunt shipping. The
arena is 2,950 lines of TypeScript plus 1.2 MB of sprite art in
`web/src/app/decks/review/battle/`, and `mobile/` has 20 Dart files and no
battle folder. Building PvP on mobile first means a second damage model and a
second quiz builder in Dart — the exact drift hazard `CLAUDE.md` warns about
for the scheduler — before a single round is playable. **Update `CLAUDE.md`
3.2's folder line when this lands**, or the next session will re-derive this
argument from scratch.

**Players meet by invite code, not by a queue.** One player creates a match and
shares a four-character code; the other enters it. No queue table, no presence,
no stale-entry reaping, no "waiting for opponent…" that never resolves. With a
handful of users an open queue renders as an infinite spinner. A queue can be
added later behind the same `matches` row — see Phase 6.

---

## Ground truth — verified against the tree at `a75bbf3`

- **`review_queue()` limits by the day's remaining caps** (`0010`, lines 91 and
  96). A duel wired through `usePracticeSession`'s default `due` mode is
  therefore *unplayable on a day the user has finished their reviews* — the
  queue comes back empty. PvP reads `practice_cards()` (`0017`) instead:
  random over every unsuspended card, no caps, no due filter.
- **`review_card()` already log-onlys `'battle'`** (`0018`, line 106: the
  branch inserts the log row and returns the card untouched). No migration is
  needed to make PvP answers non-scheduling — the value was reserved for
  exactly this and is already enforced server-side.
- **`review_log.duration_ms` has been collected since Phase 0.4** for
  `'review'` and `'quiz'` answers. This is the baseline the damage model
  scales against, and the reason 0.4 insisted it land in Phase 0 rather than
  here. There is real history now; no cold-start fudge is required.
- **Nothing in this repo uses Supabase Realtime yet.** No `channel(`, no
  `broadcast`, no publication membership. supabase-js is 2.108.2, which
  supports it. Phase 4 is greenfield.
- **`buildQuiz` is pure and synchronous** and needs only `MIN_WORDS_FOR_BATTLE`
  (4) words in the player's library. It is per-player by construction, which
  is what makes "each player quizzed from their own deck" nearly free.
- Next migration number is **`0020`**.

---

## What is reused, what is new, and the one thing that must not be reused

**Reused unchanged** — this is why the web was the right surface:

| Module | What PvP gets |
|---|---|
| `_lib/sprites.ts`, `FighterSprite`, `SPRITE_OFFSET` | 42 characters, attack chains, pose clamping |
| `_lib/projectiles.ts`, `ProjectileShot` | Ranged flight timing, already tuned |
| `_lib/quiz.ts` | `buildQuiz`, the Fisher-Yates shuffle, the 4-word floor |
| `_lib/useQuestionClock.ts` | Pause-safe clock with exact `elapsedMs()` |
| `_components/QuizOptions`, `CountdownBar`, `BattleHpStrip` | The question box, the timer, the bars |
| `_lib/feedback.ts` | Hit/crit/hurt haptics |
| `_lib/playerCharacter.ts` | The hero you already picked, shared via localStorage |

**New, and small on purpose** — `web/src/app/decks/review/duel/`:

```
_lib/duel.ts        round timing, baseline-scaled damage, win/lose/draw
_lib/bot.ts         seeded reaction time + accuracy
_lib/duel.test.ts   node --test, house style
_lib/bot.test.ts
_components/DuelArena.tsx    the two-stream round loop
_components/OpponentStrip.tsx
page.tsx
```

**Do not reuse `damage.ts`'s fold.** `deriveBattleState` /
`rollEvent` / `battleOutcome` encode player-vs-environment rules that are
wrong here, and quietly wrong rather than loudly:

- `monsterStartIndex` exists to refill a *respawning* monster's HP. A duel has
  no respawn — the opponent is one health bar for the whole match.
- Armour is granted off the whole-session streak and player HP spans the entire
  events array, both tuned for an endless gauntlet, not a 12-round match.
- `battleOutcome` returns `"cleared"` when the review queue empties. A duel
  ends on HP or on the round count; the queue has nothing to do with it.
- The fold assumes **one** answer stream. A duel has two, and each side's
  damage is a function of the *other* side's answer.

`duel.ts` is a separate module with the same discipline — pure, no I/O, folded
over resolved rounds — not a fork of `damage.ts`. The shared idea is the
architecture note at the top of `damage.ts` (roll once, fold purely), not the
code.

**Do not reuse `usePracticeSession`.** Beyond the cap problem above, it owns
`review_queue`/`review_card`/`undo_review` and a requeue-on-learning-state
rule. A duel has no undo (you cannot un-hit someone) and no requeue. It calls
`practice_cards()` once at match start and `review_card(..., 'battle')` per
answer, directly.

---

## Phase 1 — The rules, as pure functions

No UI, no network, no database. Everything here is `node --test`-able the way
the four existing battle suites are, and every number below is a first-pass
tunable, not a designed system.

### 1.1 Round timing

```ts
// 5s at round 1, tightening to a 3s floor. CLAUDE.md 3.2: "round timer 3-5s,
// tightening as the match progresses."
export function roundDurationMs(roundNo: number): number;
```

### 1.2 Baseline-scaled damage

This is the part that makes a duel fair across mismatched players, and it is
the whole reason `duration_ms` was collected in Phase 0.

```ts
export interface DuelAnswer {
  correct: boolean;
  elapsedMs: number;
  baselineMs: number;   // this player's own median, from the RPC in 1.3
}
export function roundDamage(a: DuelAnswer): number;
```

`speedRatio = baselineMs / max(elapsedMs, FLOOR_MS)`, clamped to `[0.5, 2.0]`,
times a base value. A wrong answer or a timeout deals nothing — no
self-penalty; losing the exchange is penalty enough, and a self-penalty makes a
losing streak unrecoverable.

**Both players are compared against themselves, not against each other.** A
player who habitually answers in 2 s does not beat a 6 s player by default;
each has to beat their *own* normal. Without this, PvP is a typing-speed
contest with vocabulary decoration.

### 1.3 The baseline RPC

```sql
-- 0020_pvp.sql, part 1
create function public.response_baseline() returns integer
```

Median (`percentile_cont(0.5)`), not mean — one 90-second answer where the user
walked away wrecks a mean. Over `source in ('review','quiz')`, `undone = false`,
`duration_ms` between 400 and 30000, last 90 days. **Returns null below ~20
samples**, and the client falls back to a constant; a baseline computed from
three answers is noise dressed as personalisation.

### 1.4 Streak meter

`CLAUDE.md` 3.2: "correct-answer streaks fill a meter for a bigger finisher
hit." Reuse the *shape* of `damage.ts`'s streak tiers — thresholds read from
one place, tier drives both the multiplier and the sprite pose — with duel
numbers.

### 1.5 Match resolution

```ts
export type DuelOutcome = "ongoing" | "won" | "lost" | "draw";
export function duelOutcome(state: DuelState): DuelOutcome;
```

HP to zero, or the round count runs out and the higher HP wins. **A draw is a
real outcome** — equal HP after the last round — and needs a result screen
state, or it renders as a defeat.

**Done when:** `npm test` in `web/` covers the timing curve, the ratio clamps
at both ends, the null-baseline fallback, the streak thresholds, and all four
outcomes including the draw.

---

## Phase 2 — Bot duel, entirely client-side

Playable end to end with no networking, no match tables and no Realtime. This
is the phase that makes the mode real; everything after it is multiplayer
plumbing.

### 2.1 The bot

```ts
export interface BotProfile {
  accuracy: number;          // 0..1
  meanReactionMs: number;
  reactionJitterMs: number;
}
export function botAnswer(
  profile: BotProfile, rng: () => number, roundDurationMs: number
): { correct: boolean; elapsedMs: number } | null;   // null = ran out of time
```

Takes an injected `rng` so tests are deterministic — the same trick
`damage.test.ts` uses to pin crit and evade under a stubbed `Math.random`.

**The bot must be able to time out.** If its sampled reaction exceeds the round
duration it answers nothing, exactly like a human who froze. A bot that always
answers within the timer is not a difficulty setting, it is a different game.

Three profiles. Their *names* are user-facing and their numbers are guesses
until someone plays them.

### 2.2 The arena

`DuelArena.tsx`: your question box and hero on one side, the opponent's hero
and HP on the other, one countdown between them. Cards from `practice_cards()`,
fetched once at match start.

**Damage lands at round end, not at answer time.** If the opponent's HP moves
the instant they answer, a player still holding at 4.9 s learns whether the
opponent got it right — and in a four-option quiz that is worth real
information. Show "answered" as a neutral indicator during the round; resolve
both sides together when the round closes.

### 2.3 Logging

Every duel answer calls `review_card(card_id, rating, duration_ms, log_id,
'battle')` — `'good'` for correct, `'again'` for wrong, **never `'easy'`**.
Logged, never scheduled, already enforced by `0018`. This is what makes "does a
3-second timer produce noise?" answerable with SQL later instead of assumed
now.

**Done when:** a full bot match runs to a win, a loss and a draw; `review_log`
shows the answers as `'battle'` with `due_at` unmoved; and `/decks/stats` is
unchanged after playing one.

---

## Phase 3 — Match state in Postgres

`0020_pvp.sql`, part 2. Re-runnable like every migration in this repo:
`drop policy if exists`, `drop function if exists` before any table-returning
function.

```sql
matches        id, join_code, host_id, guest_id, status, round_count,
               current_round, host_hp, guest_hp, winner_id, timestamps
match_rounds   (match_id, round_no) pk, starts_at, duration_ms
match_answers  (match_id, round_no, user_id) pk, card_id, correct,
               client_elapsed_ms, effective_ms, damage, answered_at
```

### 3.1 The join-code wrinkle

RLS scopes every table in this project to `auth.uid()`, and a guest is *not yet*
in the match they are trying to join — so they cannot select it by code. This
is the one place a `security definer` function is justified:

```sql
create function public.join_match(p_code text) returns public.matches
security definer
```

It must: match the code case-insensitively, refuse a match that already has a
guest, refuse the host joining their own match, refuse a non-`lobby` status,
and **null the code once the match starts** so a shared screenshot is not a
permanent back door. Codes come from an alphabet with no `0/O` or `1/I/L`.

Everything else stays `security invoker` with participant-scoped policies.

### 3.2 Round resolution — idempotent, first writer wins

```sql
create function public.submit_round_answer(
  p_match_id uuid, p_round_no int, p_correct boolean,
  p_client_elapsed_ms int, p_card_id uuid
) returns public.match_answers
```

`on conflict (match_id, round_no, user_id) do nothing`, then return the row
that exists — the same idempotency shape `review_card()` uses for the offline
outbox, and for the same reason: a retry after a dropped connection must not
count twice.

**Damage is computed here, not accepted from the client.** The server holds
`match_rounds.starts_at`, so it derives its own elapsed time and takes
`greatest(client_elapsed_ms, server_elapsed - latency_allowance)`, clamped into
`[MIN_HUMAN_MS, duration_ms]`.

`greatest`, not `least` — an earlier draft of this plan said `least` and that
is exactly backwards, caught by running it. Under-reporting *is* the cheat
(faster answer, more damage), so taking the smaller of the two hands the
cheater their lie and the human floor then rounds it up to the best value
available. Making the server's own clock the floor is what actually bounds it.

That is the whole anti-cheat budget, and deliberately so. `CLAUDE.md` 3.2:
both clients render the question locally, so display time is client-side no
matter what — this clamps the damage a lie can buy, and does not pretend to
prevent the lie. There is no ladder to protect.

### 3.3 Two implementations of the damage rules, honestly managed

After this phase Postgres is authoritative for PvP and `duel.ts` is
authoritative for bot matches. They must produce the same numbers or a bot
fight will not feel like a real one.

Handle it the way `CLAUDE.md`'s Stack section already specifies for the
scheduler: **a shared golden fixture** — a JSON table of
`(correct, elapsedMs, baselineMs, streak) → expected damage` that both
`duel.test.ts` and a SQL check run. Not optional; this is precisely the "never
let two implementations drift unchecked" case.

### 3.4 Abandonment

An opponent who closes the tab must not hang the match. Three consecutive
rounds with no answer from one side ends it: `forfeit_match(p_match_id)`, status
`abandoned`, the other player wins. Bounded by the round schedule, so no
background job is needed.

**Done when:** two browser profiles play a full match; a duplicate
`submit_round_answer` changes nothing; a forged `client_elapsed_ms` of 1 deals
no more than a fast honest answer; and closing one tab ends the match within
three rounds.

---

## Phase 4 — Realtime

One channel per match: `match:<id>`. Postgres Changes on `match_answers` and
`matches`, filtered to that match id, so each client sees the opponent's answer
and the HP change without polling.

**The step that gets forgotten:** both tables must be added to the
`supabase_realtime` publication in the migration. Without it, subscriptions
connect successfully and simply never fire — no error anywhere.

The round schedule is issued once, at match start, as rows in `match_rounds`.
Clients read it and run their own clocks against `starts_at`. Nothing is
invoked per round except `submit_round_answer`, which is a Postgres function,
not an edge function — `CLAUDE.md` 3.2's first correction.

**Note what the schedule does not contain: questions.** Each player draws their
own card for round N from their own `practice_cards()` fetch. The schedule is
*timing*, shared; the *content* is per-player, and that is what keeps a
200-word deck fair against a 2,000-word one.

**Done when:** an answer on one screen moves the HP bar on the other within a
few hundred ms, and a refresh mid-match rejoins at the correct round.

---

## Phase 5 — Balance and the things that only show up in play

None of this can be reasoned out; it needs two people and an evening.

- Bot difficulty numbers. Every value in 2.1 is a guess.
- Base damage and the ratio clamps — is a 12-round match ending on HP or on
  the round count more often than not?
- Whether the streak finisher is exciting or decides matches by round four.
- The `MIN_WORDS_FOR_BATTLE` gate, checked **per player** at create and at
  join. A host with 400 words and a guest with 3 must fail at the lobby, not
  at round one.
- Mongolian strings throughout (`web/src/app/decks/_lib/strings.ts`), and the
  `ReviewModeModal` / `ReviewModePicker` rows switched from inert to real —
  both currently render the PvP row with `T.comingSoon` and no `href`.

---

## Phase 6 — Only if there are ever enough players

Open matchmaking, as a queue that writes the same `matches` row the invite-code
path already creates. One match lifecycle, two ways in. Not worth building
before the invite path has been played enough to know the rules are right.

---

## Deliberately not doing

- **A ladder, ranking or ELO.** Nothing above is built to withstand a motivated
  cheater, and a ladder is what creates one.
- **Spectating, rematch chains, tournaments.** Scope.
- **PvP answers touching SM-2.** Non-negotiable, and already enforced in
  Postgres rather than left to client discipline. Anyone "tidying up" by
  collapsing `'battle'` into `'quiz'` would silently start scheduling on
  3-second guesses — see `CLAUDE.md` 3.1b's table.
- **A Flutter port**, until the rules have stopped moving. When it happens it
  is a new client against the same tables and RPCs, not a second rules engine.

---

## What was built, and what three things changed on contact

Phases 1–4 are in the tree. Three parts of the plan above were wrong and were
corrected by running them, which is the reason to record them here rather than
quietly fix them:

**1. The anti-cheat clamp was backwards.** This plan said
`least(client_elapsed, server_elapsed)`. Under-reporting *is* the cheat — a
faster answer deals more damage — so `least` hands the cheater their lie, and
the human floor then rounds it up to the best value obtainable. A forged 1 ms
answer became a 350 ms answer: maximum damage. It is `greatest(client,
server − latency_allowance)` now, and a forged 1 ms against a round the server
saw take 2 s is charged 1502 ms. Caught by the first real query, not by review.

**2. The lifecycle functions had to become `SECURITY DEFINER`.** The plan had
`join_match` as the only one. But the three tables grant SELECT and nothing
else — deliberately, so a client cannot zero the opponent's HP — which leaves
`begin_round`/`submit_round_answer` unable to insert and
`resolve_round`/`forfeit_match` unable to `select ... for update`, since that
needs the withheld UPDATE privilege. Under invoker rights they failed for
*legitimate participants*. Found by running the whole lifecycle as the
`authenticated` role instead of as `postgres`, which is the only way this shows
up at all.

**3. Baselines are frozen on the match row.** The plan had `resolve_round`
computing each player's median when it needed it. Two problems: RLS means a
client cannot compute its opponent's median, so it could not predict damage at
all; and a review finished mid-match would move the baseline and put the
client's prediction permanently at odds with the server. `matches` now carries
`host_baseline_ms` / `guest_baseline_ms`, set once on create and join.

### Verified

- All 20 migrations apply in sequence to a clean Postgres 16, and `0020`
  re-applies cleanly on top of itself.
- The full lifecycle runs as the `authenticated` role: create → join by code →
  begin → both submit → resolve. A non-participant gets `not your match` from
  all four functions and sees zero rows in all three tables. Neither
  participant can write HP directly — no UPDATE policy, so it silently affects
  nothing.
- A twelve-round match plays out to a knockout at round 9 with the right
  winner, and further `resolve_round` calls are no-ops.
- **The golden fixture holds**: 484 cases, `duel_damage()` and `roundDamage()`
  agree on every one.
- 12,000 simulated matches: 94% / 51% / 12% win rates against the three bots,
  averaging ~12 rounds. The difficulties are genuinely different and matches go
  the distance rather than ending in an early knockout.

### What is left — phase 5, and it is the part that needs a person

- **Nobody has played it.** The arena has never been rendered. The round
  rhythm, the 1.5s resolution hold, the two-beat attack/flinch and the whole
  lobby are unexercised by anything but the type checker.
- **Two real players have never been in a match together.** The server side is
  verified with SQL; the Realtime path, the waiting room and the code entry are
  not.
- Bot numbers, damage constants and the streak tiers are first-pass guesses.
- No projectiles in the duel arena — `projectileFor` is right there and unused,
  so a ranged hero swings at nothing. Cosmetic, and deliberate: the impact
  timing machinery it needs is the fiddliest part of `BattleArena`.

## Acceptance

Two people on two machines play a duel to a decisive end. Both see the same
final HP. `review_log` has their answers as `'battle'`, every `due_at` is
untouched, and `/decks/stats` shows exactly the numbers it showed beforehand.
