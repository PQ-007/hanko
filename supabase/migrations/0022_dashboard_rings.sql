-- Two new numbers for the dashboard's StreakHero rings:
--   new_goal           — the user's existing new_per_day preference, exposed
--                         so the dashboard can show "goal" without a new
--                         stored setting of its own.
--   new_reviewed_today — new cards reviewed today (state_before = 'new'
--                         only). A relearning/review-card answer does not
--                         advance this number — it's specifically about
--                         working through today's new-word allowance.
--
-- Both ride along on due_summary(), which already computes both internally
-- (v_new_cap, v_new_done) and simply wasn't returning them.
--
-- Safe to re-run: due_summary is dropped and recreated (OUT params changed,
-- so create-or-replace can't be used — same reason 0012 and 0018 restate it).

drop function if exists public.due_summary(uuid, timestamptz);

create function public.due_summary(
  p_deck_id uuid        default null,
  p_at      timestamptz default now()
) returns table (
  due_now            integer,  -- what a session started at p_at would serve
  review_due         integer,  -- review/learning cards due, ignoring caps
  new_due            integer,  -- new cards available, ignoring caps
  review_remaining   integer,  -- that day's unspent review allowance
  new_remaining      integer,  -- that day's unspent new-card allowance
  new_goal           integer,  -- profiles.new_per_day — today's new-card goal
  new_reviewed_today integer   -- new cards (state_before='new') answered today
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
    and source in ('review', 'quiz')
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

  review_remaining   := greatest(v_rev_cap - v_rev_done, 0);
  new_remaining      := greatest(v_new_cap - v_new_done, 0);
  due_now            := least(review_due, review_remaining) + least(new_due, new_remaining);
  new_goal           := v_new_cap;
  new_reviewed_today := v_new_done;

  return next;
end;
$$;
