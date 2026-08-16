-- "How much is due?" answered by the same rules the review session uses.
--
-- The dashboard counted `words.due_at <= now()` client-side, which knows
-- nothing about the day cutoff or the per-day caps — so it would happily report
-- 47 due while the session serves 20. Two different answers to the same
-- question is worse than either answer alone.
--
-- Mobile needs exactly this number too, for the "N cards due" notification, so
-- it belongs on the server rather than in either client.

-- Dropped first: a table-returning function's row type can't be changed by
-- `create or replace`, and this one will gain columns as the dashboard grows.
drop function if exists public.due_summary(uuid);

create function public.due_summary(p_deck_id uuid default null)
returns table (
  due_now          integer,  -- what a session started now would actually serve
  review_due       integer,  -- review/learning cards due, ignoring caps
  new_due          integer,  -- new cards available, ignoring caps
  review_remaining integer,  -- today's unspent review allowance
  new_remaining    integer   -- today's unspent new-card allowance
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

  select
    count(*) filter (where state_before = 'new'),
    count(*) filter (where state_before is not null and state_before <> 'new')
  into v_new_done, v_rev_done
  from public.review_log
  where user_id = v_user
    and source = 'review'
    and undone = false
    and reviewed_at >= v_day_start;

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
    and c.due_at <= now();

  review_remaining := greatest(v_rev_cap - v_rev_done, 0);
  new_remaining    := greatest(v_new_cap - v_new_done, 0);
  due_now := least(review_due, review_remaining) + least(new_due, new_remaining);

  return next;
end;
$$;
