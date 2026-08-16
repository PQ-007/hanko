-- Reviews per day, bucketed by the SRS day rather than the calendar day.
--
-- Two problems this fixes.
--
-- First, disagreement between clients: the web dashboard groups review_log by
-- *local midnight* (localDateKey in web/src/app/decks/_lib/dates.ts), so mobile
-- computing its own streak would be a second, subtly different answer to the
-- same question.
--
-- Second, disagreement with the scheduler: everything else in this system rolls
-- the day over at the user's cutoff hour (4am by default). Grouping activity at
-- midnight means a review at 01:00 starts a new streak day while the scheduler
-- still considers it yesterday — so a late-night session could show a streak the
-- review queue doesn't believe in. Same boundary everywhere is the whole point
-- of having put the cutoff in the database.

drop function if exists public.review_activity(integer);

create function public.review_activity(p_days integer default 400)
returns table (
  day     date,
  reviews integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_tz     text;
  v_cutoff integer;
begin
  select prefs.tz, prefs.cutoff
    into v_tz, v_cutoff
  from public.srs_prefs(v_user) prefs;

  -- No aliases in the select list on purpose: the RETURNS TABLE columns are
  -- plpgsql variables, so naming a result column `day` here would be ambiguous.
  return query
  select
    ((public.srs_day_start(l.reviewed_at, v_tz, v_cutoff))
      at time zone coalesce(v_tz, 'UTC'))::date,
    count(*)::integer
  from public.review_log l
  where l.user_id = v_user
    and l.source = 'review'      -- battle/drill answers never count as study
    and l.undone = false          -- nor do answers the user took back
    and l.reviewed_at >= now() - make_interval(days => p_days)
  group by 1
  order by 1;
end;
$$;
