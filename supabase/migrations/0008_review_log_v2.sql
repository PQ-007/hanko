-- Make review_log carry what later phases need, and make it safe to write from
-- a device that goes offline mid-session.

alter table public.review_log
  add column if not exists card_id         uuid references public.cards on delete cascade,
  -- Response time, measured from answer-reveal to rating. Battle mode scales
  -- damage against each player's own historical average, so this has to be
  -- collected from day one or that mechanic starts with no baseline. It is also
  -- the main input a future FSRS migration needs.
  add column if not exists duration_ms     integer,
  -- Pre-answer scheduling state. The scalars are for analytics/FSRS; the jsonb
  -- snapshot is what undo_review() restores from, since repetitions, lapses,
  -- learning_step and due_at all have to come back exactly.
  add column if not exists state_before    text,
  add column if not exists ease_before     numeric(4,2),
  add column if not exists interval_before integer,
  add column if not exists card_before     jsonb,
  -- Keeps gamified answers out of scheduling and out of the stats dashboard.
  -- Answers given under a 3-second battle timer are noise; feeding them into
  -- SM-2 would corrupt real scheduling.
  add column if not exists source          text not null default 'review',
  -- The table has no delete policy by design (history can't be rewritten from
  -- a client), so an undone answer is marked rather than removed.
  add column if not exists undone          boolean not null default false;

alter table public.review_log
  drop constraint if exists review_log_source_check;
alter table public.review_log
  add constraint review_log_source_check
  check (source in ('review', 'battle', 'drill'));

-- Idempotency: `id` is already the primary key, and public.review_card() now
-- inserts with `on conflict (id) do nothing`. Clients MUST generate the id on
-- the device and reuse it when retrying, so an answer replayed after an offline
-- gap is applied exactly once. Without this a retry double-counts the review,
-- inflating streaks and the activity heatmap with no way to repair it.

-- Dashboard reads are always "my reviews since <date>, excluding undone ones".
drop index if exists review_log_user_reviewed_idx;
create index if not exists review_log_user_reviewed_idx
  on public.review_log (user_id, reviewed_at desc) where undone = false;

create index if not exists review_log_card_idx
  on public.review_log (card_id, reviewed_at desc);

-- Backfill card_id for history written before the cards table existed. Every
-- pre-existing word has exactly one recognition card (0006).
update public.review_log l
   set card_id = c.id
  from public.cards c
 where c.word_id = l.word_id
   and c.template = 'recognition'
   and l.card_id is null;

-- NOTE for the dashboard: existing queries in web/src/app/decks/ must add
-- `.eq("undone", false)` and `.eq("source", "review")`, otherwise undone
-- answers and future battle/drill answers will show up in streaks and the
-- heatmap.
