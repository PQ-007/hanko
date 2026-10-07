-- 0027 — a leaderboard of everyone, not just friends.
--
-- Strangers see each other here, so it shows less than the friends board:
--   * handle, level score and ELO only — no real name, no Google picture, no
--     daily activity, no user id;
--   * only people who chose a handle AND share (profiles.share_activity) —
--     the existing switch now also takes you off the global board;
--   * your own row always comes back, with your true rank, even outside the
--     top N.
--
-- A public board is what makes farming worth it (PVP.md "Deliberately not
-- doing"), so user_xp now caps the non-scheduling part — drill and battle
-- answers, which have no daily limit of their own — at 100 XP per day.
-- Scheduling answers stay uncapped: review_queue() already limits them per
-- day, and they are the recall the board is meant to reward.
--
-- Safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. user_xp with the daily cap on practice XP (same signature as 0026)
-- ---------------------------------------------------------------------------

create or replace function public.user_xp(p_user uuid, p_since timestamptz default null)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select (
    -- Recall that schedules: uncapped (review_queue caps it per day already).
    coalesce((
      select sum(case when l.rating <> 'again' then 10 else 2 end)
      from public.review_log l
      where l.user_id = p_user and not l.undone
        and l.source in ('review', 'quiz')
        and (p_since is null or l.reviewed_at >= p_since)
    ), 0)
    -- Practice that doesn't schedule (writing lessons, free practice, duel
    -- answers): 2 each, at most 100 a day.
    + coalesce((
      select sum(least(per_day, 100)) from (
        select count(*) * 2 as per_day
        from public.review_log l
        where l.user_id = p_user and not l.undone
          and l.source not in ('review', 'quiz')
          and (p_since is null or l.reviewed_at >= p_since)
        group by (l.reviewed_at at time zone 'UTC')::date
      ) d
    ), 0)
    + coalesce((
      select count(*) * 5 from public.words w
      where w.user_id = p_user and not w.deleted
        and (p_since is null or w.date_added >= p_since)
    ), 0)
    + coalesce((
      select count(*) * 20 from public.learned_kanji k
      where k.user_id = p_user and (p_since is null or k.learned_at >= p_since)
    ), 0)
    + coalesce((
      select sum(case
        when m.winner_id = p_user then 50
        when m.winner_id is null and m.status = 'finished' then 25
        when m.status = 'finished' then 10
        else 0
      end)
      from public.matches m
      where (m.host_id = p_user or m.guest_id = p_user)
        and m.guest_id is not null
        and m.status in ('finished', 'abandoned')
        and (p_since is null or m.finished_at >= p_since)
    ), 0)
  )::integer;
$$;

revoke execute on function public.user_xp(uuid, timestamptz) from public;
revoke execute on function public.user_xp(uuid, timestamptz) from authenticated;

-- ---------------------------------------------------------------------------
-- 2. The global board
-- ---------------------------------------------------------------------------
-- p_by: 'week' (XP over the last 7 days), 'total' (all-time XP) or 'elo'.
-- Returns the top p_limit, plus the caller's own row when it falls outside.

drop function if exists public.global_leaderboard(text, integer);
create function public.global_leaderboard(p_by text default 'week', p_limit integer default 50)
returns table (
  rank      integer,
  handle    text,
  is_me     boolean,
  is_friend boolean,
  xp_total  integer,
  xp_week   integer,
  elo       integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not signed in'; end if;
  if p_by not in ('week', 'total', 'elo') then raise exception 'bad ranking'; end if;

  return query
  with players as (
    select p.id, p.handle,
           public.user_xp(p.id) as xp_total,
           public.user_xp(p.id, now() - interval '7 days') as xp_week,
           coalesce(r.elo, 1000) as elo
    from public.profiles p
    left join public.player_ratings r on r.user_id = p.id
    where p.handle is not null and p.share_activity
  ),
  ranked as (
    select pl.*,
           rank() over (order by case p_by
             when 'week' then pl.xp_week
             when 'total' then pl.xp_total
             else pl.elo end desc)::integer as rnk
    from players pl
  )
  select r.rnk, r.handle, r.id = v_me, public.are_friends(v_me, r.id),
         r.xp_total, r.xp_week, r.elo
  from ranked r
  where r.rnk <= least(greatest(p_limit, 1), 100) or r.id = v_me
  order by r.rnk, r.handle;
end;
$$;

grant execute on function public.global_leaderboard(text, integer) to authenticated;
