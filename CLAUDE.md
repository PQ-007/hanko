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

**Status: migrations `0006`–`0010` are written and verified** against Postgres 16
(applied in sequence from a clean database, then exercised for day-cutoff
boundaries, learning-step transitions, interval growth, lapses, idempotent
replay, undo restoration, daily caps, and RLS scoping). Still open: 0.6's port of
the web practice screen onto the RPC, and 0.7's sync-cursor fix.

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

### 0.7 Fix the sync cursor, and test the upsert
In `src/sync.js`:
- `lastSyncedAt` is the client's local `Date.now()` compared against
  server-generated `updated_at`. A device clock running ahead of Postgres puts
  the cursor in the future and those rows are **never** pulled again. Use the
  server clock, or `max(updated_at)` over the pulled rows.
- Write an explicit test for what PostgREST's `resolution=merge-duplicates` does
  to columns absent from the payload. Absent columns are believed to be left
  untouched (they aren't in the INSERT column list), but if that's wrong, every
  word edit in the extension silently resets that card's schedule. Confirm it,
  don't assume it. 0.1 makes this moot for SRS state, but not for word fields.

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

## Phase 2 — Parity polish

- Streaks/stats screens matching `web/src/app/decks/stats/`
- Deck management: create, edit, delete, import
- Audio: precache the day's queue from the `word-audio` bucket so review works
  offline on a commute. Requires the audio route to accept a bearer token.
- Offline: **online-first with a local cache**, not a third sync engine. Cache
  the day's queue in Drift and queue up `review_card` calls for replay. Do not
  port `src/sync.js`'s last-write-wins model into Dart — two hand-written sync
  engines diverge silently, and 0.1 already keeps review state off that path.

---

## Phase 3 — Gamified modes (optional; must not delay Phases 0–2)

### 3.1 Ship the cheap gamification first
Higher retention per hour of work than PvP, and none of the networking risk:
- Daily goal + streak, with a freeze/shield
- "Speed round" drill over already-mature cards — `source='drill'`, no
  scheduling impact
- Leech-rescue sessions targeting high-`lapses` cards

### 3.2 Online 1v1 battle mode
Fast-paced vocabulary duel, in its own feature folder
(`mobile/lib/features/battle/`) so it never entangles with the review code.

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
2. **Distractor generation is the unsolved problem.** A 12-word deck cannot
   produce three plausible wrong answers, and obviously-wrong options make the
   mode boring no matter how good the netcode is. Needs a global distractor pool
   (JMdict frequency list) with a same-part-of-speech, similar-length heuristic.
   Solve this before building the match loop.
3. **Right-size the anti-cheat.** Both clients render the question locally, so
   display time is client-side regardless. The honest model: the server
   timestamps round start, derives latency from its own receive time, and clamps
   damage to a sane range. Don't build more than that for a game with no ladder.

**Battle answers never feed scheduling.** They are logged with `source='battle'`
and excluded from SRS state and the stats dashboard. Guesses under a 3-second
timer are noise, and mixing them into SM-2 corrupts real scheduling.

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

- **SM-2 is not "what Anki uses"** — the comment at the top of `web/src/lib/srs.ts`
  is out of date. Anki has defaulted to FSRS since 23.10, and FSRS reaches the
  same retention with meaningfully fewer reviews. Don't claim Anki parity in
  user-facing copy. Phase 0.4 makes a later FSRS switch a data migration.
- `/api/lookup` is unauthenticated and proxies Jisho. Rate-limit it before mobile
  traffic hits it.
- The extension has **no build step** — edits to `src/sync.js` must be copied
  verbatim into both `chrome/` and `firefox/`.
- Never commit `config.js` or `.env.local`. The publishable key is safe to ship;
  RLS is what protects the data, so any new table needs its policies written in
  the same migration.
