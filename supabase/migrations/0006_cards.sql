-- Split scheduling state out of `words` into its own `cards` table.
--
-- Until now one word == one card: the SRS columns lived directly on words
-- (0004_srs.sql). That makes reverse cards (meaning -> term), kanji -> reading
-- cards and audio cards impossible without a rewrite, which is why Anki models
-- this as note -> cards. Doing the split while there is little review history
-- is cheap; doing it later is not.
--
-- It also removes a sync hazard: the extension (src/sync.js) upserts whole
-- `words` rows with last-write-wins and maps none of the SRS columns. Once
-- scheduling lives in `cards`, which the extension never touches, an extension
-- write can no longer land on top of review state.

create table if not exists public.cards (
  id            uuid primary key default gen_random_uuid(),
  word_id       uuid not null references public.words on delete cascade,
  user_id       uuid not null references auth.users on delete cascade,
  -- Which side of the word this card drills. Only 'recognition' is generated
  -- today; the rest exist so adding them later is a data change, not a schema
  -- change.
  template      text not null default 'recognition'
                  check (template in ('recognition', 'recall', 'reading', 'audio')),
  -- Anki-style card state. 'new' has never been answered; 'learning' is inside
  -- the intraday steps; 'review' is on a day-scale interval; 'relearning' is a
  -- lapsed review card working back through the relearn steps.
  state         text not null default 'new'
                  check (state in ('new', 'learning', 'review', 'relearning')),
  learning_step smallint not null default 0,   -- index of the next step to serve
  ease_factor   numeric(4,2) not null default 2.5,
  interval_days integer not null default 0,
  repetitions   integer not null default 0,
  lapses        integer not null default 0,
  suspended     boolean not null default false,
  due_at        timestamptz not null default now(),
  last_reviewed_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (word_id, template)
);

-- The queue read: "my cards that are due, soonest first".
create index if not exists cards_due_idx
  on public.cards (user_id, due_at) where suspended = false;
create index if not exists cards_word_id_idx on public.cards (word_id);

alter table public.cards enable row level security;

-- Dropped first so this file can be re-run after a partial apply: `create
-- policy` and `create trigger` both fail outright if the object already exists,
-- and hand-applying migrations one at a time in the SQL editor makes partial
-- applies likely.
drop policy if exists "cards_select_own" on public.cards;
create policy "cards_select_own" on public.cards
  for select using (auth.uid() = user_id);
drop policy if exists "cards_insert_own" on public.cards;
create policy "cards_insert_own" on public.cards
  for insert with check (auth.uid() = user_id);
drop policy if exists "cards_update_own" on public.cards;
create policy "cards_update_own" on public.cards
  for update using (auth.uid() = user_id);
drop policy if exists "cards_delete_own" on public.cards;
create policy "cards_delete_own" on public.cards
  for delete using (auth.uid() = user_id);

drop trigger if exists cards_touch_updated_at on public.cards;
create trigger cards_touch_updated_at
  before update on public.cards
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Backfill: one recognition card per existing word, carrying its current
-- schedule across so nobody's progress resets.
-- ---------------------------------------------------------------------------
insert into public.cards (
  word_id, user_id, template, state,
  ease_factor, interval_days, repetitions, due_at, last_reviewed_at, created_at
)
select
  w.id, w.user_id, 'recognition',
  case when w.repetitions = 0 then 'new' else 'review' end,
  w.ease_factor, w.interval_days, w.repetitions, w.due_at, w.last_reviewed_at,
  w.date_added
from public.words w
on conflict (word_id, template) do nothing;

-- ---------------------------------------------------------------------------
-- Every new word gets its recognition card automatically. The extension and the
-- currently deployed web build insert into `words` and know nothing about
-- `cards`, so this has to happen server-side or captured words would never
-- become reviewable.
--
-- SECURITY DEFINER so it also works for service-role and backfill inserts; the
-- inserted user_id is copied from the word, so it can't be used to write a row
-- into someone else's account.
-- ---------------------------------------------------------------------------
create or replace function public.create_default_card()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.cards (word_id, user_id, template, due_at)
  values (new.id, new.user_id, 'recognition', coalesce(new.due_at, now()))
  on conflict (word_id, template) do nothing;
  return new;
end;
$$;

drop trigger if exists words_create_default_card on public.words;
create trigger words_create_default_card
  after insert on public.words
  for each row execute function public.create_default_card();

-- NOTE: words.ease_factor / interval_days / repetitions / due_at /
-- last_reviewed_at are deliberately left in place for one release. The deployed
-- extension and web build still read them, and public.review_card() mirrors
-- scheduling back into them. Drop them only after both clients ship against
-- `cards`.
