# Hanko — project brief

## Repo layout (monorepo)
This is `vocab-decks-extension/`. `mobile/` is a new Flutter app living alongside
the existing `chrome/`, `firefox/`, `web/` front ends, shared `src/`, and
`supabase/migrations/`. Claude Code launched at the repo root can see all of it
in one session — no copying files between folders needed.

## What this project is
Hanko is a Japanese vocabulary spaced-repetition system with three surfaces:

- **Capture** — browser extension (`chrome/`, `firefox/`) grabs a word off any
  page and files it into a deck
- **Manage + review** — Next.js web app (`web/`) with deck CRUD, an SRS practice
  screen, and a stats dashboard
- **Review on the go** — the new Flutter app (`mobile/`)

All three share **one Supabase project** (auth, Postgres, Storage). Do not create
a second backend. The mobile app is a new client on the existing schema, not a
new system.

---

## Ground truth — already investigated, do not re-derive

These were verified against the checked-in code. Trust this section over any
description in a prompt; re-read the named file if you need detail.

**Schema** (`supabase/migrations/`, 5 migrations)
- `profiles` (1:1 with `auth.users`, auto-created by trigger), `folders`,
  `decks`, `words`, `review_log`
- Every table is RLS-scoped to `auth.uid()`. This is what makes it safe for the
  extension and mobile to hit the REST API directly with the publishable key.
- `words` carries the SRS state inline: `ease_factor`, `interval_days`,
  `repetitions`, `due_at`, `last_reviewed_at` (`0004_srs.sql`).
  **Phase 0 moves this to a `cards` table — see below.**
- `review_log` is append-only (insert + select policies only, no update/delete).
- Private Storage bucket `word-audio`, objects at `<user_id>/<word_id>.mp3`.

**SRS scheduler** — `web/src/lib/srs.ts`
- Already a pure function with no Supabase/React imports. It is **not** entangled
  with extension code; the extension does no scheduling at all.
- SM-2 with Anki-style Hard/Easy multipliers and a graduated interval floor.
- Also exports `gradeFor()` (new/F–A mastery tiers) used by the dashboard.

**Auth** — Google OAuth only
- Web: `web/src/app/login/page.tsx`, cookie session via `@supabase/ssr`
  (`web/src/lib/supabase/server.ts`, `web/src/proxy.ts`).
- Extension: no in-extension OAuth. `src/sync.js` `signIn()` opens
  `/extension/connect` in a tab; that page (`web/src/app/extension/connect/`)
  runs the implicit flow and `postMessage`s the tokens to `content.js`, which
  forwards them to the background to store.
- There is no email/password or magic-link path today.

**Sync** — `src/sync.js` (canonical; copied verbatim into `chrome/` and
`firefox/`, which have no build step)
- Plain `fetch` against Supabase REST + Auth, no supabase-js bundle.
- Local mirror in `storage.local`, tombstone deletes, **last-write-wins at row
  granularity** keyed on `updatedAt`.
- Push/pull cursor is `lastSyncedAt`, set from the client's local `Date.now()`.
- `wordToRow` maps term/reading/meaning/meaning_mn only — **it does not map any
  SRS column**.

**Reusable server endpoints** (`web/src/app/api/`)
- `GET /api/lookup?term=` — Jisho lookup, **no auth**, callable from Flutter as-is
- `GET /api/translate` — EN→MN via keyless Google Translate
- `/api/decks/[id]/apkg`, `/api/decks/[id]/txt`, `/api/words/[id]/audio` — these
  use the **cookie-based** SSR client and will not work from Flutter until they
  accept a bearer token.

---

## Phase 0 — schema and shared scheduling (do this first, no Flutter code)

Every item here is cheap now and expensive after mobile ships and there are three
clients and a year of review history. All of it is done in the existing repo with
the web app as the test client.

**Status: migrations `0006`–`0011` are written and verified** against Postgres 16
(applied in sequence from a clean database and re-applied to confirm they're
safely re-runnable, then exercised for day-cutoff boundaries, learning-step
transitions, interval growth, lapses, idempotent replay, undo restoration, daily
caps, queue/summary agreement, and RLS scoping).

**The web app is fully ported**: the practice screen runs on `review_queue()` /
`review_card()` / `undo_review()`, the dashboard's due count comes from
`due_summary()` so it can't disagree with the session, and `profiles.timezone`
is kept in step with the browser (`_components/EnsureTimezone.tsx`) — without
that the day cutoff silently runs in UTC.

**Phase 0 is complete.** Migrations 0006–0011 are applied to the live Supabase
project and a real review session on the web app works against them. The sync
cursor fix (0.7) is in `src/sync.js` and copied into `chrome/` and `firefox/`.

Not yet done, and deliberately deferred: the extension has not been repackaged
or reloaded with the new `sync.js`, so the cursor fix isn't live in the browser
until you reload the unpacked extension (or ship a new build).

### 0.1 Split cards out of words
`words` conflates "the vocabulary item" with "one scheduled card", which
permanently forecloses reverse cards, kanji→reading cards, and audio cards — the
things that make a Japanese SRS app worth using. Anki's note→cards model exists
for this reason.

```sql
create table public.cards (
  id            uuid primary key default gen_random_uuid(),
  word_id       uuid not null references public.words on delete cascade,
  user_id       uuid not null references auth.users on delete cascade,
  template      text not null default 'recognition',  -- recognition | recall | reading | audio
  ease_factor   numeric(4,2) not null default 2.5,
  interval_days integer not null default 0,
  repetitions   integer not null default 0,
  lapses        integer not null default 0,
  suspended     boolean not null default false,
  due_at        timestamptz not null default now(),
  last_reviewed_at timestamptz,
  unique (word_id, template)
);
```
Backfill one `recognition` card per existing word, carrying the current SRS
columns across. Leave the old columns on `words` in place for one release so the
deployed extension and web build keep working, then drop them.

This also removes the sync hazard in 0.5 by construction: the extension writes
`words`, never `cards`, so its last-write-wins upserts can no longer sit on top
of review state.

### 0.2 Day-granular scheduling with a per-user cutoff
`srs.ts` does `due.setDate(due.getDate() + interval_days)`, so a card answered at
23:50 falls due at 23:50 the next day. Symptoms: "due today" drifts through the
day, cards reappear minutes after a user finishes at night, and users see
different queues in different timezones. Mobile is where timezones actually
change, so fix it before mobile exists.

- Add `timezone text` and `day_cutoff_hour int not null default 4` to `profiles`
- Normalize `due_at` to the user's next cutoff boundary rather than a raw offset
- Queue reads select `due_at <= <current cutoff boundary>`, not `now()`

### 0.3 Learning steps, daily caps, interval fuzz
- **Learning steps**: new cards currently jump straight to a 1-day interval.
  Add short intraday steps (1m / 10m) before graduation.
- **Daily caps**: `new_per_day` / `reviews_per_day` on `profiles`. Without them a
  500-word import produces a 500-card wall and the user quits.
- **Fuzz**: ±5% on computed intervals. Three lines, and it prevents cards added
  on the same day from clumping into the same review day forever.

### 0.4 Make review_log carry what later phases need
```sql
alter table public.review_log
  add column duration_ms   integer,      -- Phase 3 damage scaling depends on this
  add column ease_before   numeric(4,2),
  add column interval_before integer,
  add column card_id       uuid references public.cards on delete cascade,
  add column source        text not null default 'review';  -- review | battle | drill
```
- `duration_ms` must land **in Phase 0**, not Phase 3. Battle damage scales with
  each player's own average response time; logging it now means months of real
  baselines exist by the time battle mode ships, instead of needing a cold-start
  fudge.
- `source` keeps gamified/speed-pressured answers out of scheduling and stats.
- The before-state columns are what a future FSRS migration needs; without them
  the switch is a rewrite instead of a data migration.

### 0.5 Idempotent review writes
`review_log` has no idempotency key, and mobile will retry inserts after going
offline — double-counting reviews, inflating streaks and the heatmap, with no
update/delete policy available to repair it. Have the client generate the row
`id` and insert with `on conflict (id) do nothing`.

### 0.6 One transactional review path
```sql
review_card(p_card_id uuid, p_rating text, p_duration_ms int, p_log_id uuid)
  returns public.cards
```
Updates the card and appends the log row in a single transaction, server-side.

This is the single source of truth for scheduling. It fixes a live bug in
`web/src/app/decks/practice/_components/PracticeSession.tsx`, where the `words`
update and the `review_log` insert are two unatomic calls and the insert
swallows every error via `.then(undefined, () => {})` — a failed insert silently
loses history. It also means **mobile never re-implements SM-2**. Port the web
practice screen onto this RPC in Phase 0 and verify the dashboard still matches.

### 0.7 Fix the sync cursor (done)
`src/sync.js` kept one cursor, `lastSyncedAt`, written from the client's local
`Date.now()` and compared against server-generated `updated_at`. A device clock
running ahead of Postgres put the cursor in the future, and every row committed
inside that window was filtered out of all later pulls — silent, permanent loss.

It now keeps two cursors, because they live in two different clock domains:
- `lastPushedAt` — local time, selects our own edits (which are stamped locally)
- `lastPulledAt` — server time, read from the REST `Date` response header, minus
  a 5s margin

Both are captured before the store snapshot, and the push filter is `>=` rather
than `>`, so an edit can't fall through the gap between two syncs. Upgrading
resets `lastPulledAt` to 0, forcing one full re-pull that repairs anything the
old cursor already skipped.

`node src/sync.test.js` covers all of it (device ahead, device behind, local
edits under skew) with no dependencies or test runner. It fails on every case
against the pre-fix version — worth keeping, since none of this is visible by
clicking around.

**Answered, so nobody re-investigates it:** PostgREST's
`resolution=merge-duplicates` leaves columns absent from the payload untouched.
Verified against a real PostgREST + Postgres: an extension-shaped word upsert
(no SRS columns in the body) updated `meaning`/`meaning_mn` and left
`ease_factor`, `interval_days`, `repetitions` and `due_at` exactly as they were.
Extension edits never clobbered schedules.

**Phase 0 acceptance**: web practice screen runs entirely through `review_card`,
the stats dashboard numbers are unchanged, extension sync round-trips a word edit
without disturbing card state, and due counts stay stable across a simulated
23:50 → 00:10 rollover.

---

## Phase 1 — Core SRS mobile app

- Auth against the existing Supabase project
- Deck list + card CRUD on the same tables the extension and web app use,
  including manual word entry — the only way words are added on mobile
- Review screen: Again / Hard / Good / Easy, each answer a single `review_card`
  RPC call with `duration_ms` measured from card reveal. Fetch the queue with
  `review_queue()`; never re-implement "what's due" client-side.
- Local notification for "N cards due" — this is the largest retention lever on
  mobile and costs about two hours

**Success criterion**: review 5 cards on mobile, then load `/decks/stats` on the
web app — the activity heatmap increments and the due counts drop. (The old
"the extension sees the same history" phrasing was untestable; the extension is a
capture tool with no review-history UI.)

**Auth is the likely time sink.** Google OAuth on Flutter is `google_sign_in` +
`supabase.auth.signInWithIdToken`, not the web redirect flow. It needs separate
Android and iOS OAuth client IDs, the Android SHA-1 fingerprint registered, and
the deep-link redirect added to Supabase's allow list. Budget a day.

**If you ship on iOS**, App Store review requires Sign in with Apple alongside
any third-party sign-in. Add it as a second Supabase provider before submitting.

---

## Capture stays on the extension — deliberate scope decision

**Mobile does not capture words.** No share-target intent, no OCR, no in-app
browser. Words enter the system two ways only:

1. The browser extension, automated as far as it can go
2. Manual entry in the web app or mobile app

Don't propose mobile capture features; the split is intentional — desktop
captures, mobile reviews.

Worth doing on the extension side, since it is now the only automated capture
surface: `chrome/content.js` already holds the full selection and throws away
everything but the word. Add `words.context_sentence` and `words.source_url` and
populate them at capture time. Context and cloze cards retain substantially
better than bare word→meaning pairs, and the data is free at the moment of
capture — but only the extension is positioned to collect it.

---

## Phase 2 — Parity polish (done)

- Streaks/stats screens matching `web/src/app/decks/stats/`. Both clients read
  one server-side `review_activity()` RPC (0013) rather than each computing
  streaks client-side — that fixed a real bug, where the web bucketed activity
  by local midnight while the scheduler rolls the day over at the 4am cutoff,
  so a 1am review could extend a streak the scheduler didn't believe in yet.
- Deck management: create, rename, delete on mobile. Delete matches the web
  app's semantics exactly (`DeckHeader.tsx`) — tombstone the words, then the
  deck; cards are left alone so `review_queue()` drops them by filtering
  through `words.deleted`, meaning a restored deck would come back with its
  schedules intact rather than every card resetting to new.
- **Import: deliberately skipped.** There was no import anywhere in the
  project to match — only export (`/api/decks/[id]/apkg`, `/txt`) — and the
  export format doesn't round-trip cleanly (`frontText`/`backText` flatten
  reading and meaning_mn in ways that are lossy to parse back). The extension
  already covers bulk capture, so this isn't worth inventing a new format for.
- Audio: precache the day's queue from the `word-audio` bucket so review works
  offline on a commute. Required the audio route to accept a bearer token
  (`web/src/lib/supabase/bearer.ts`) — it now accepts either the web's cookie
  session or `Authorization: Bearer`, scoped by RLS to the caller's own token,
  not a service-role bypass.
- Offline: **online-first with a local cache**, not a third sync engine
  (`mobile/lib/core/offline_review.dart`). Drift caches the last queue fetched
  (replaced wholesale, never merged) and a durable outbox replays queued
  answers in order. This is safe only because `review_card()` is idempotent on
  the device-generated log id — an offline answer retried after reconnecting
  can't double-count a review or inflate a streak.

---

## Phase 3 — Gamified modes (optional; must not delay Phases 0–2)

### 3.1 Ship the cheap gamification first (done)
Higher retention per hour of work than PvP, and none of the networking risk.
Migration `0014_gamification.sql`, verified against real Postgres — the 21-day
mature-card cutoff, the 4-lapse leech threshold, drill answers leaving
`interval_days`/`due_at` completely untouched while still logging, leech
rescue genuinely rescheduling via the default `source='review'`, and RLS
blocking cross-user reads on both new RPCs.

- **Streak freeze**: `profiles.streak_freezes` (default 2), read-only capacity
  rather than a spend/earn economy — deliberately deferred, see the migration's
  comment. `currentStreak()` in both `mobile/lib/features/stats/streaks.dart`
  and `web/src/app/decks/_lib/dates.ts` bridges up to that many single-day
  gaps, and **only if the bridge reconnects to a real active day** — a
  dangling bridge that runs out of budget before finding one is stripped back
  out. Without that check a brand-new account with zero reviews ever would
  show a fabricated streak from its default freeze allotment alone; caught by
  a test (`streaks_test.dart`), not by inspection.
- **Speed round** (`mature_cards()` RPC + `SpeedRoundScreen`): mature is
  `interval_days > 21`, matching `gradeFor()`'s existing B/A cutoff in
  `web/src/lib/srs.ts` rather than inventing a second definition. Random
  order, ignores `due_at` and the daily caps — it's bonus practice, not part
  of the scheduled workload, so it must not compete with it for the cap. No
  offline queue and no undo: `source='drill'` answers change nothing
  server-side, so there is no scheduling state to protect.
- **Leech rescue** (`leech_cards()` RPC + `LeechRescueScreen`): lapses ≥ 4 —
  a deliberately low, unresearched starting threshold (Anki's own default is
  8, calibrated for years of imported history this app doesn't have yet),
  worth revisiting once there's real lapse data. Also ignores `due_at`
  (reaching a leech before the scheduler would is the point), but unlike the
  speed round this uses the *default* `source='review'`: a successful rescue
  is real practice and genuinely reschedules the card. Online-only by design —
  a proactive opt-in session failing outright when offline is an acceptable,
  honest limit, unlike the main due queue which must never fail offline.

**That "what day is today" gap is now closed.** Both clients used to start the
streak walk from the device clock (`DateTime.now()` / `new Date()`) while
`review_activity()` bucketed by the SRS-day cutoff, so between local midnight
and `day_cutoff_hour` they walked from a day the server had not opened yet —
usually rescued by the "skip to yesterday if today's empty" rule, but by
accident, and not at all on a device whose clock or timezone disagreed with the
profile. `current_srs_day()` (0019) returns the same day key the activity rows
are grouped by; the web dashboard and mobile's stats screen both start from it
and fall back to the device date only if the RPC is missing. The two walks are
pinned against each other case-for-case (`dates.test.ts` / `streaks_test.dart`).

### 3.1b Monster Hunt — the web quiz-battle mode (done)

Built on the web (`web/src/app/decks/review/`), reached from the **Давтах** nav
tab. Four-option multiple choice against an animated opponent, 10-second Kahoot
timer, HP bars, crit/evade/armour driven by the correct-answer streak, and a
roster of 42 sprite characters. It is a **skin over the real review session**:
it consumes the same `usePracticeSession` hook as the classic screen, so
`review_queue()` / `review_card()` / `undo_review()` are called once, from one
place, and there is no second scheduler.

Do not confuse it with 3.2 below — different mode, different `source` value:

| Mode | Source | Reschedules? |
|---|---|---|
| Classic review | `review` | yes |
| **Monster Hunt (scored)** | **`quiz`** | **yes** |
| Free practice / speed round | `drill` | no |
| PvP duel (3.2, unbuilt) | `battle` | no |

**`quiz` is not a downgrade of `review`.** Monster Hunt is real recall practice
that happens to be timed; it schedules, counts toward streaks, fills the
heatmap and spends the daily caps, exactly like classic review
(`0018_quiz_source.sql`). It is labelled solely so the two can be *compared* —
a four-option question has a 25% guess floor, and `review_log` already carries
`ease_before`/`interval_before` from 0.4, so "does the timed mode schedule as
reliably?" is answerable with SQL instead of guessed at.

For the same reason, a battle answer **cannot grade `easy`**. Speed still
drives damage across three tiers, but `scheduleRating()` in `BattleArena.tsx`
caps what reaches `review_card()` at `good`: inside 3.3 seconds, one correct
answer in four is luck, and luck must not buy interval.

**Distractors come from the player's own word library**, synchronously and with
no network call per question (`_lib/quiz.ts`, `MIN_WORDS_FOR_BATTLE = 4`). The
Jisho-backed `distractor_cache` an earlier draft of 3.2 called for was built,
found too slow in real play, and dropped — `0015` created that table and `0016`
drops it. Do not resurrect it; **item 2 under 3.2 below is solved.**

### 3.2 Online 1v1 battle mode (built, unplayed — see `PVP.md`)
Fast-paced vocabulary duel, in its own feature folder so it never entangles
with the review code.

**It ships on the web, in `web/src/app/decks/review/duel/`.** The
`mobile/lib/features/battle/` this section used to name was chosen before
Monster Hunt existed; the arena is now 2,950 lines of TypeScript plus 1.2 MB of
sprite art under `web/`, and `mobile/` has no battle folder at all. Building it
on Flutter first would mean a second damage model and a second quiz builder in
Dart before a single round was playable. A Flutter client comes later, against
the same tables and RPCs.

`PVP.md` holds the plan and what changed on contact with a real Postgres.
Phases 1–4 are in the tree: `/decks/review/duel` plays a bot with no network at
all, and an invite-code match against a real player via `0020_pvp.sql` and one
Realtime channel. **Nobody has played it** — that is phase 5.

Two things a future session must not "tidy up":

- **`duel_damage()` in 0020 is a deliberate mirror of `roundDamage()` in
  `duel/_lib/duel.ts`.** Bot duels resolve client-side with no network; PvP
  duels resolve in Postgres because the client cannot be trusted. The guard is
  `duel/_lib/duel.fixture.json` — 484 cases, pinned from the TypeScript by
  `duel.test.ts` and from the SQL by `supabase/tests/duel_damage_fixture.sql`.
  Regenerating the fixture to make a failure go away launders a real behaviour
  change into a green test.
- **The duel does not reuse `damage.ts` or `usePracticeSession`, on purpose.**
  Both encode PvE rules that are quietly wrong for a duel — a respawning
  monster's HP refill, a queue-empty end condition, and a fold that assumes one
  answer stream where a duel has two. `usePracticeSession` additionally reads
  `review_queue()`, which is capped by the day's remaining allowance, so a duel
  wired through it is unplayable on exactly the day you have finished your
  reviews.

- Two players (or player vs. bot), each with an HP bar; center timer and a
  multiple-choice question box
- Each round both players are quizzed **from their own deck**, not a shared pool
  — keeps fights fair across mismatched deck sizes
- Speed-scaled damage, measured against the player's own historical average from
  `review_log.duration_ms` (this is why 0.4 exists)
- Wrong answer = no damage, or a brief self-penalty
- Correct-answer streaks fill a meter for a bigger finisher hit
- Round timer 3–5s, tightening as the match progresses
- **Ship the bot opponent first** (tunable reaction time and accuracy). It makes
  the mode playable from day one and defers all matchmaking work.

Three things the original design got wrong:

1. **Don't invoke an edge function per round.** At a 3–5s round timer that is a
   cold-start-prone invocation every few seconds per match. Have an edge function
   start the *match* and issue the round schedule; resolve each round with an
   idempotent Postgres function both clients call, first writer wins. Transport
   is one Supabase Realtime channel per match.
2. **Distractor generation — solved, inherit it.** This was the open problem;
   it no longer is. `_lib/quiz.ts` builds four options from the player's own
   library with a Fisher-Yates shuffle and a four-word floor, synchronously and
   with no per-question network call. The JMdict pool this bullet used to
   demand was never needed. (The shuffle matters: the original
   `.sort(() => Math.random() - 0.5)` measured 36/17/16/31 across the four
   slots, enough bias that guessing a slot beat recall. Guarded by
   `quiz.test.ts`.)
3. **Right-size the anti-cheat.** Both clients render the question locally, so
   display time is client-side regardless. The honest model: the server
   timestamps round start, derives latency from its own receive time, and clamps
   damage to a sane range. Don't build more than that for a game with no ladder.

**PvP answers never feed scheduling.** They are logged with `source='battle'`
and excluded from SRS state and the stats dashboard. Guesses under a 3-second
timer are noise, and mixing them into SM-2 corrupts real scheduling.

This is specifically about **PvP**, not about Monster Hunt. `'battle'` is
reserved for this unbuilt mode and is the one value `review_card()` will not
schedule on; Monster Hunt uses `'quiz'` and does. Anyone "tidying up" by
collapsing the two would silently stop the app's main practice mode from
scheduling anything, with nothing erroring — see 3.1b.

---

## Stack

- **Flutter** in `mobile/`, `supabase_flutter`, **Riverpod** for state
- **Drift** for local storage (prefer over Isar — maintenance has been unreliable)
- **Scheduling lives in Postgres** (`review_card`). If offline scheduling later
  requires a client-side copy, keep the Dart implementation as a mirror validated
  against a shared golden-test fixture — a JSON table of
  `(state, rating) → expected result` that both the TypeScript and Dart test
  suites run. Never let two implementations drift unchecked.
- Reuse the existing Supabase project throughout. No backend rewrite.

## Standing notes

- **`PVP.md` is the worked plan for Phase 3.2**, the only phase big enough
  to need its own file. Read it before touching anything duel-shaped.

- **`IMPROVEMENTS.md` is the "what next" list** — the prioritised follow-up
  plan written after Monster Hunt shipped (migrations to confirm, the
  multiple-choice guess floor that currently writes real SM-2 intervals, the
  missing web test suite, PvP). Anything in it that becomes permanent truth
  moves here and gets deleted from there.

- **SM-2 is not "what Anki uses"** — the comment at the top of `web/src/lib/srs.ts`
  is out of date. Anki has defaulted to FSRS since 23.10, and FSRS reaches the
  same retention with meaningfully fewer reviews. Don't claim Anki parity in
  user-facing copy. Phase 0.4 makes a later FSRS switch a data migration.
- **`web/` has tests now**: `npm test` in `web/` runs `node --test` over
  `src/**/*.test.ts`. No runner, no dependency, no build step — Node 22 strips
  types natively, and the four battle logic modules import only types. They
  cover the damage fold, the quiz builder's shuffle uniformity, the monster
  shuffle bag and pose resolution. Verified to fail on injected regressions,
  not just to pass.
- Migrations are applied by hand in the Supabase SQL editor (there is no
  `supabase` CLI or `config.toml` in this repo), so **every migration must be
  safe to re-run**: guard policies and triggers with `drop ... if exists`, and
  precede any table-returning function with `drop function if exists` —
  `create or replace` cannot change a function's OUT-parameter row type.
- `/api/lookup` is unauthenticated and proxies Jisho. Rate-limited per IP with
  an in-process token bucket (`web/src/lib/rateLimit.ts`) — enough to stop it
  being an open proxy, but per-instance, so it is not a defence against a
  distributed caller. Revisit if the app is ever deployed to more than one
  instance.
- The extension has **no build step** — edits to `src/sync.js` must be copied
  verbatim into both `chrome/` and `firefox/`.
- Never commit `config.js` or `.env.local`. The publishable key is safe to ship;
  RLS is what protects the data, so any new table needs its policies written in
  the same migration.
