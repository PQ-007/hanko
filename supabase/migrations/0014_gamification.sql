-- Phase 3.1 — the cheap gamification, per the project brief: "higher
-- retention per hour of work than PvP, and none of the networking risk."
-- Three independent pieces; none of them touch the scheduler's own tables.

-- ---------------------------------------------------------------------------
-- Streak freeze
-- ---------------------------------------------------------------------------
-- A small fixed pool of "grace days" per user. Deliberately NOT a
-- spend-and-refill economy: earning/spending logic is a real design surface
-- (how many per week? does a freeze expire? do you buy them?) that the brief
-- doesn't specify, and getting it wrong would need a second migration to fix
-- stored state. Instead this is a pure capacity number that the streak
-- calculation reads without ever mutating it — see streaks.dart /
-- dates.ts, which both bridge up to this many single-day gaps when walking
-- backward from today. Easy to extend into a real economy later; the column
-- is the only piece that has to exist now.
alter table public.profiles
  add column if not exists streak_freezes integer not null default 2;

alter table public.profiles
  drop constraint if exists profiles_streak_freezes_check;
alter table public.profiles
  add constraint profiles_streak_freezes_check check (streak_freezes >= 0);

-- ---------------------------------------------------------------------------
-- Speed round: mature cards, independent of due_at and the daily caps
-- ---------------------------------------------------------------------------
-- "Mature" mirrors gradeFor()'s B/A cutoff in web/src/lib/srs.ts
-- (interval_days > 21) — reusing an existing threshold rather than inventing a
-- second definition of "mature" for this one feature.
--
-- Randomized order on purpose: review_queue() is soonest-due-first because
-- that ordering matters for real scheduling, but a drill has no such
-- constraint, and a fixed order would mean drilling the same cards first every
-- time.
drop function if exists public.mature_cards(uuid, integer);

create function public.mature_cards(
  p_deck_id uuid    default null,
  p_limit   integer default 30
) returns table (
  card_id       uuid,
  word_id       uuid,
  deck_id       uuid,
  template      text,
  state         text,
  learning_step smallint,
  due_at        timestamptz,
  interval_days integer,
  repetitions   integer,
  ease_factor   numeric,
  term          text,
  reading       text,
  meaning       text,
  meaning_mn    text,
  audio_path    text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    c.id, c.word_id, w.deck_id, c.template, c.state, c.learning_step, c.due_at,
    c.interval_days, c.repetitions, c.ease_factor,
    w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = auth.uid()
    and c.suspended = false
    and w.deleted = false
    and c.state = 'review'
    and c.interval_days > 21
    and (p_deck_id is null or w.deck_id = p_deck_id)
  order by random()
  limit p_limit;
$$;

-- ---------------------------------------------------------------------------
-- Leech rescue: high-lapse cards, independent of due_at
-- ---------------------------------------------------------------------------
-- Anki's own default leech threshold is 8 lapses; this app has far less review
-- history behind it (a fresh SM-2 rewrite, not an imported multi-year Anki
-- collection), so 8 would surface almost nothing for most accounts today.
-- 4 is a deliberate, lower starting point — a tunable constant, not a
-- researched value, and worth revisiting once there's real lapse data to look
-- at.
--
-- Ordered worst-first: the cards most in need of rescue lead the session
-- rather than being buried at the end of it.
drop function if exists public.leech_cards(uuid, integer);

create function public.leech_cards(
  p_deck_id uuid    default null,
  p_limit   integer default 30
) returns table (
  card_id       uuid,
  word_id       uuid,
  deck_id       uuid,
  template      text,
  state         text,
  learning_step smallint,
  due_at        timestamptz,
  interval_days integer,
  repetitions   integer,
  ease_factor   numeric,
  term          text,
  reading       text,
  meaning       text,
  meaning_mn    text,
  audio_path    text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    c.id, c.word_id, w.deck_id, c.template, c.state, c.learning_step, c.due_at,
    c.interval_days, c.repetitions, c.ease_factor,
    w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = auth.uid()
    and c.suspended = false
    and w.deleted = false
    and c.lapses >= 4
    and (p_deck_id is null or w.deck_id = p_deck_id)
  order by c.lapses desc, c.due_at
  limit p_limit;
$$;
