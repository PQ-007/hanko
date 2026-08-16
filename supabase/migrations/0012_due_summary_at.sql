-- Let due_summary() answer for a moment other than "now".
--
-- The mobile reminder is scheduled hours ahead ("9am tomorrow: N cards due"),
-- so it needs the count as it will be *then*, not as it is when the app happens
-- to be open. Computing that on the client would mean re-deriving the day
-- cutoff and the cap accounting a third time, which is exactly what putting
-- them in the database was meant to avoid.
--
-- Everything else is unchanged: p_at defaults to now(), so existing callers
-- (the web dashboard, the mobile deck list) are unaffected.

drop function if exists public.due_summary(uuid);
drop function if exists public.due_summary(uuid, timestamptz);

create function public.due_summary(
  p_deck_id uuid        default null,
  p_at      timestamptz default now()
) returns table (
  due_now          integer,  -- what a session started at p_at would serve
  review_due       integer,  -- review/learning cards due, ignoring caps
  new_due          integer,  -- new cards available, ignoring caps
  review_remaining integer,  -- that day's unspent review allowance
  new_remaining    integer   -- that day's unspent new-card allowance
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

  -- The SRS day containing p_at. For a reminder scheduled after the next
  -- cutoff this is a *later* day than today, so the caps come back unspent —
  -- which is the correct forecast: tomorrow's allowance is untouched.
  v_day_start := public.srs_day_start(p_at, v_tz, v_cutoff);

  select
    count(*) filter (where state_before = 'new'),
    count(*) filter (where state_before is not null and state_before <> 'new')
  into v_new_done, v_rev_done
  from public.review_log
  where user_id = v_user
    and source = 'review'
    and undone = false
    and reviewed_at >= v_day_start
    and reviewed_at <= p_at;

  select
    count(*) filter (where c.state <> 'new'),
    count(*) filter (where c.state = 'new')
  into review_due, new_due
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = v_user
    and c.suspended = false
    and w.deleted = false
    and (p_deck_id is null or w.deck_id = p_deck_id)
    and c.due_at <= p_at;

  review_remaining := greatest(v_rev_cap - v_rev_done, 0);
  new_remaining    := greatest(v_new_cap - v_new_done, 0);
  due_now := least(review_due, review_remaining) + least(new_due, new_remaining);

  return next;
end;
$$;
