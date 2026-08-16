-- Per-user scheduling preferences + a day boundary that isn't "whatever time
-- you happened to answer".
--
-- srs.ts schedules with `due.setDate(due.getDate() + interval_days)`, so a card
-- answered at 23:50 falls due at 23:50 the next day. Consequences: the "due
-- today" count drifts through the day, cards reappear minutes after a user
-- finishes a late-night session, and the same account shows different queues in
-- different timezones. Anki solves this with a day cutoff (4am by default).
-- Mobile is where timezones actually change, so this lands before mobile does.

alter table public.profiles
  add column if not exists timezone        text,               -- IANA name; null = UTC
  add column if not exists day_cutoff_hour integer not null default 4,
  add column if not exists new_per_day     integer not null default 20,
  add column if not exists reviews_per_day integer not null default 200;

alter table public.profiles
  drop constraint if exists profiles_day_cutoff_hour_check;
alter table public.profiles
  add constraint profiles_day_cutoff_hour_check
  check (day_cutoff_hour between 0 and 23);

-- Start of the SRS day containing p_at, for a user in p_tz with cutoff p_cutoff.
--
--   23:50 local, cutoff 4  -> 04:00 today   (still today's SRS day)
--   02:00 local, cutoff 4  -> 04:00 *yesterday* (the day hasn't rolled over yet)
--
-- STABLE rather than IMMUTABLE: timezone conversion depends on the tz database.
create or replace function public.srs_day_start(
  p_at     timestamptz,
  p_tz     text,
  p_cutoff integer
) returns timestamptz
language sql
stable
set search_path = public
as $$
  select (
    date_trunc('day', (p_at at time zone coalesce(p_tz, 'UTC'))
                      - make_interval(hours => p_cutoff))
    + make_interval(hours => p_cutoff)
  ) at time zone coalesce(p_tz, 'UTC');
$$;

-- Scheduling prefs for a user, with defaults applied even when the profile row
-- is missing (the left join against a one-row source guarantees exactly one
-- result row rather than zero).
-- Dropped first for the same reason as review_queue: a table-returning
-- function's row type can't be changed by `create or replace`.
drop function if exists public.srs_prefs(uuid);

create function public.srs_prefs(p_user uuid)
returns table (
  tz              text,
  cutoff          integer,
  new_per_day     integer,
  reviews_per_day integer
)
language sql
stable
set search_path = public
as $$
  select
    coalesce(p.timezone, 'UTC'),
    coalesce(p.day_cutoff_hour, 4),
    coalesce(p.new_per_day, 20),
    coalesce(p.reviews_per_day, 200)
  from (select 1) one
  left join public.profiles p on p.id = p_user;
$$;
