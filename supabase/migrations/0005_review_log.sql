-- Append-only log of every review answer, so the dashboard can show real
-- activity history. words.last_reviewed_at only ever holds the *latest*
-- review for a card, which can't reconstruct a per-day activity calendar
-- (a word reviewed 30 times would appear on exactly one day).

create table if not exists public.review_log (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users on delete cascade,
  word_id      uuid not null references public.words on delete cascade,
  deck_id      uuid not null references public.decks on delete cascade,
  rating       text not null check (rating in ('again', 'hard', 'good', 'easy')),
  -- SRS state produced by this answer, so history stays meaningful even if
  -- the word is later edited or rescheduled.
  interval_days integer not null default 0,
  reviewed_at  timestamptz not null default now()
);

-- The dashboard's main read: "all my reviews since <date>", newest first.
create index if not exists review_log_user_reviewed_idx
  on public.review_log (user_id, reviewed_at desc);

alter table public.review_log enable row level security;

-- Insert + select only: the log is append-only by design (no update/delete
-- policies), so history can't be silently rewritten from the browser.
create policy "review_log_select_own" on public.review_log
  for select using (auth.uid() = user_id);
create policy "review_log_insert_own" on public.review_log
  for insert with check (auth.uid() = user_id);
