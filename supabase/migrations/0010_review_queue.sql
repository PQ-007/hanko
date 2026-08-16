-- The review queue, with the day cutoff and daily caps applied server-side.
--
-- The web practice screen currently reads `words` with `due_at <= now()` and a
-- hard-coded limit of 20 (PracticeSession.tsx). That has no notion of a day
-- boundary and no cap, so importing 500 words produces a 500-card wall — the
-- reliable way to make someone quit an SRS app. Putting the queue here means
-- web and mobile can't disagree about what's due.

-- Dropped first: `create or replace` cannot change a function's OUT-parameter
-- row type, so re-running this file after the column list changed fails with
-- "cannot change return type of existing function". Dropping makes the file
-- safe to re-apply as the queue's shape evolves.
drop function if exists public.review_queue(uuid, integer);

create function public.review_queue(
  p_deck_id uuid    default null,
  p_limit   integer default 60
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
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_tz        text;
  v_cutoff    integer;
  v_new_cap   integer;
  v_rev_cap   integer;
  v_day_start timestamptz;
  v_new_done  integer;
  v_rev_done  integer;
begin
  select prefs.tz, prefs.cutoff, prefs.new_per_day, prefs.reviews_per_day
    into v_tz, v_cutoff, v_new_cap, v_rev_cap
  from public.srs_prefs(v_user) prefs;

  v_day_start := public.srs_day_start(now(), v_tz, v_cutoff);

  -- How much of today's allowance is already spent. Rows written before
  -- 0008 have a null state_before and count toward neither bucket.
  select
    count(*) filter (where state_before = 'new'),
    count(*) filter (where state_before is not null and state_before <> 'new')
  into v_new_done, v_rev_done
  from public.review_log
  where user_id = v_user
    and source = 'review'
    and undone = false
    and reviewed_at >= v_day_start;

  return query
  with due as (
    select
      c.id, c.word_id, c.template, c.state, c.learning_step, c.due_at,
      c.interval_days, c.repetitions, c.ease_factor,
      w.deck_id, w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path
    from public.cards c
    join public.words w on w.id = c.word_id
    where c.user_id = v_user
      and c.suspended = false
      and w.deleted = false
      and (p_deck_id is null or w.deck_id = p_deck_id)
      and c.due_at <= now()
  ),
  -- Learning and relearning cards are due within minutes and count against the
  -- review allowance, not the new-card one: they're already in flight and
  -- dropping them mid-session is worse than going slightly over.
  -- Every reference below is alias-qualified on purpose: the RETURNS TABLE
  -- columns are plpgsql variables, so a bare `state` or `due_at` here is
  -- ambiguous and fails at runtime.
  reviews as (
    select * from due where due.state <> 'new'
    order by due.due_at
    limit greatest(v_rev_cap - v_rev_done, 0)
  ),
  news as (
    select * from due where due.state = 'new'
    order by due.due_at
    limit greatest(v_new_cap - v_new_done, 0)
  )
  select
    q.id, q.word_id, q.deck_id, q.template, q.state, q.learning_step, q.due_at,
    q.interval_days, q.repetitions, q.ease_factor,
    q.term, q.reading, q.meaning, q.meaning_mn, q.audio_path
  from (select * from reviews union all select * from news) q
  order by (q.state = 'new'), q.due_at   -- overdue reviews first, then new cards
  limit p_limit;
end;
$$;
