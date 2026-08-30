-- What day is it, according to the scheduler?
--
-- Both clients walk the streak backwards from their own clock — new Date() on
-- the web, DateTime.now() on mobile — while review_activity() buckets by the
-- user's SRS day, which rolls over at profiles.day_cutoff_hour (4am by
-- default). Between local midnight and that cutoff the two disagree by exactly
-- one day: the client starts its walk on a key the server has not opened yet.
--
-- Usually invisible, because both clients already fall back to yesterday when
-- "today" has no activity — so the walk quietly self-corrects. It does not
-- self-correct when the user reviews inside that window: those answers land on
-- the previous SRS day, the client looks for them under the next one, finds
-- them one step down, and the streak is right by accident rather than by
-- construction. It also cannot self-correct at all on a device whose clock or
-- timezone disagrees with the profile.
--
-- The fix is not more client arithmetic. It is asking the one component that
-- already knows: the same srs_day_start() the queue, the caps and the heatmap
-- are all derived from. One round trip, one definition, two clients.
--
-- Returns the same key shape review_activity() groups by — a date in the
-- user's own timezone — so the result is directly comparable to those rows
-- without any further conversion on either client.
--
-- Safe to re-run.

create or replace function public.current_srs_day(p_at timestamptz default now())
returns date
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_tz     text;
  v_cutoff integer;
begin
  select prefs.tz, prefs.cutoff
    into v_tz, v_cutoff
  from public.srs_prefs(auth.uid()) prefs;

  return ((public.srs_day_start(p_at, v_tz, v_cutoff))
           at time zone coalesce(v_tz, 'UTC'))::date;
end;
$$;
