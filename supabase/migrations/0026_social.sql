-- 0026 — friends, XP, ELO, learned kanji, and conceding a duel.
--
-- Mobile's social tab: find friends by handle (never by email), a friends-only
-- leaderboard ranked by XP or ELO, each friend's activity (words added and
-- reviewed today, words and kanji learned), and learned kanji kept on the
-- server instead of only on the phone.
--
-- Privacy model, enforced here rather than trusted to clients:
--   * Nobody but accepted friends ever sees another user's anything.
--   * Email is never returned by any function in this file.
--   * profiles.share_activity = false hides a user's numbers even from
--     friends (their handle and name still show, so the friendship is
--     visible to both sides).
--
-- Cheat model: XP is DERIVED on read from rows the server already owns
-- (review_log, words, learned_kanji, matches) — there is no XP column for a
-- client to write. ELO lives in its own table with no write grant at all; only
-- the match-end trigger changes it. A friends-only board has little to
-- protect, and this keeps it that way (PVP.md "Deliberately not doing" was
-- written against a public ladder).
--
-- Safe to re-run: every object is guarded or create-or-replace, and
-- table-returning functions are dropped first.

-- ---------------------------------------------------------------------------
-- 1. Profile: a public handle and a sharing switch
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists handle         text,
  add column if not exists share_activity boolean not null default true;

-- 3–20 of a-z, 0-9, _ — typed on a phone keyboard and read aloud.
alter table public.profiles drop constraint if exists profiles_handle_format;
alter table public.profiles add constraint profiles_handle_format
  check (handle is null or handle ~ '^[a-z0-9_]{3,20}$');

create unique index if not exists profiles_handle_key on public.profiles (handle);

-- ---------------------------------------------------------------------------
-- 2. Friendships
-- ---------------------------------------------------------------------------

create table if not exists public.friendships (
  requester_id uuid not null references auth.users on delete cascade,
  addressee_id uuid not null references auth.users on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

create index if not exists friendships_addressee_idx on public.friendships (addressee_id);

alter table public.friendships enable row level security;

-- Each row is visible to its two people only. No write policy: requests are
-- made, answered and removed through the functions below, which check who is
-- asking.
drop policy if exists "friendships_select_party" on public.friendships;
create policy "friendships_select_party" on public.friendships
  for select using (auth.uid() in (requester_id, addressee_id));

-- True when a and b are accepted friends (either direction).
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. Learned kanji (from the writing lessons)
-- ---------------------------------------------------------------------------

create table if not exists public.learned_kanji (
  user_id    uuid not null references auth.users on delete cascade,
  kanji      text not null check (char_length(kanji) = 1),
  learned_at timestamptz not null default now(),
  primary key (user_id, kanji)
);

alter table public.learned_kanji enable row level security;

drop policy if exists "learned_kanji_select_own" on public.learned_kanji;
drop policy if exists "learned_kanji_insert_own" on public.learned_kanji;
drop policy if exists "learned_kanji_delete_own" on public.learned_kanji;
create policy "learned_kanji_select_own" on public.learned_kanji
  for select using (auth.uid() = user_id);
create policy "learned_kanji_insert_own" on public.learned_kanji
  for insert with check (auth.uid() = user_id);
create policy "learned_kanji_delete_own" on public.learned_kanji
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 4. ELO — written only by the match-end trigger
-- ---------------------------------------------------------------------------

create table if not exists public.player_ratings (
  user_id uuid primary key references auth.users on delete cascade,
  elo     integer not null default 1000,
  games   integer not null default 0,
  wins    integer not null default 0,
  losses  integer not null default 0,
  draws   integer not null default 0
);

alter table public.player_ratings enable row level security;

drop policy if exists "player_ratings_select_own" on public.player_ratings;
create policy "player_ratings_select_own" on public.player_ratings
  for select using (auth.uid() = user_id);

alter table public.matches add column if not exists rating_applied boolean not null default false;

-- Standard ELO, K = 32. Runs BEFORE the status change is written, so marking
-- the match rated happens in the same row write — a re-sent update can't
-- apply a result twice. A lobby nobody joined (no guest) is never rated.
create or replace function public.apply_match_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  k constant numeric := 32;
  v_host_elo  integer;
  v_guest_elo integer;
  v_expected  numeric;
  v_score     numeric;  -- host's score: 1 win, 0.5 draw, 0 loss
  v_delta     integer;
begin
  if new.rating_applied
     or new.guest_id is null
     or new.status not in ('finished', 'abandoned')
     or old.status = new.status then
    return new;
  end if;

  insert into public.player_ratings (user_id) values (new.host_id), (new.guest_id)
  on conflict (user_id) do nothing;

  select elo into v_host_elo from public.player_ratings where user_id = new.host_id for update;
  select elo into v_guest_elo from public.player_ratings where user_id = new.guest_id for update;

  v_score := case
    when new.winner_id = new.host_id then 1
    when new.winner_id = new.guest_id then 0
    else 0.5
  end;
  v_expected := 1 / (1 + power(10, (v_guest_elo - v_host_elo) / 400.0));
  v_delta := round(k * (v_score - v_expected));

  update public.player_ratings set
    elo    = elo + v_delta,
    games  = games + 1,
    wins   = wins + (v_score = 1)::int,
    losses = losses + (v_score = 0)::int,
    draws  = draws + (v_score = 0.5)::int
  where user_id = new.host_id;

  update public.player_ratings set
    elo    = elo - v_delta,
    games  = games + 1,
    wins   = wins + (v_score = 0)::int,
    losses = losses + (v_score = 1)::int,
    draws  = draws + (v_score = 0.5)::int
  where user_id = new.guest_id;

  new.rating_applied := true;
  return new;
end;
$$;

drop trigger if exists matches_apply_rating on public.matches;
create trigger matches_apply_rating
  before update of status on public.matches
  for each row execute function public.apply_match_rating();

-- ---------------------------------------------------------------------------
-- 5. Conceding — the caller LOSES
-- ---------------------------------------------------------------------------
-- forfeit_match (0020) is called by the player who is still there, and makes
-- them the winner. A player who walks away must not call that — it would
-- hand them the win, which with ELO is a free rating for leaving a losing
-- match. This is the leaving player's call.

drop function if exists public.concede_match(uuid);
create function public.concede_match(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches;
begin
  select * into v_match from public.matches
  where id = p_match_id and (host_id = auth.uid() or guest_id = auth.uid())
  for update;
  if not found then
    raise exception 'not your match';
  end if;
  if v_match.status not in ('lobby', 'active') then
    return v_match;
  end if;

  update public.matches set
    status      = 'abandoned',
    finished_at = now(),
    winner_id   = case
      when v_match.guest_id is null then null
      when v_match.host_id = auth.uid() then v_match.guest_id
      else v_match.host_id
    end
  where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Friend requests
-- ---------------------------------------------------------------------------

-- Returns one of: sent, accepted (they had already asked you), already,
-- not_found, self.
drop function if exists public.send_friend_request(text);
create function public.send_friend_request(p_handle text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_other uuid;
begin
  if v_me is null then raise exception 'not signed in'; end if;
  select id into v_other from public.profiles where handle = lower(trim(p_handle));
  if v_other is null then return 'not_found'; end if;
  if v_other = v_me then return 'self'; end if;

  if exists (select 1 from public.friendships
             where requester_id = v_me and addressee_id = v_other)
     or public.are_friends(v_me, v_other) then
    return 'already';
  end if;

  -- They already asked: asking back accepts.
  update public.friendships set status = 'accepted'
  where requester_id = v_other and addressee_id = v_me and status = 'pending';
  if found then return 'accepted'; end if;

  insert into public.friendships (requester_id, addressee_id) values (v_me, v_other)
  on conflict do nothing;
  return 'sent';
end;
$$;

-- The addressee answers a pending request.
drop function if exists public.respond_friend_request(uuid, boolean);
create function public.respond_friend_request(p_from uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_accept then
    update public.friendships set status = 'accepted'
    where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
  else
    delete from public.friendships
    where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
  end if;
end;
$$;

-- Removes a friend, cancels your request, or declines theirs — either side.
drop function if exists public.remove_friend(uuid);
create function public.remove_friend(p_other uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.friendships
  where (requester_id = auth.uid() and addressee_id = p_other)
     or (requester_id = p_other and addressee_id = auth.uid());
$$;

-- Pending requests in both directions, with what's needed to show them.
drop function if exists public.friend_requests();
create function public.friend_requests()
returns table (other_id uuid, handle text, name text, image text, incoming boolean, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.handle, p.name, p.image, f.addressee_id = auth.uid(), f.created_at
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where f.status = 'pending'
    and auth.uid() in (f.requester_id, f.addressee_id)
  order by f.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- 7. XP and the friends overview
-- ---------------------------------------------------------------------------
-- XP weights. Recall that schedules is worth the most; practice that doesn't
-- (drills, duel answers) is worth a little, so it counts without being the
-- fastest way up.

create or replace function public.user_xp(p_user uuid, p_since timestamptz default null)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select (
    coalesce((
      select sum(case
        when l.source in ('review', 'quiz') and l.rating <> 'again' then 10
        when l.source in ('review', 'quiz') then 2
        else 2   -- drill (writing lessons, free practice) and battle answers
      end)
      from public.review_log l
      where l.user_id = p_user and not l.undone
        and (p_since is null or l.reviewed_at >= p_since)
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
        else 0     -- conceded or abandoned: nothing for the one who left
      end)
      from public.matches m
      where (m.host_id = p_user or m.guest_id = p_user)
        and m.guest_id is not null
        and m.status in ('finished', 'abandoned')
        and (p_since is null or m.finished_at >= p_since)
    ), 0)
  )::integer;
$$;

-- You and your accepted friends, with each one's numbers for the leaderboard
-- and the activity cards. A friend who turned sharing off shows with handle
-- and name only; their numbers are null.
drop function if exists public.friend_overview();
create function public.friend_overview()
returns table (
  user_id          uuid,
  handle           text,
  name             text,
  image            text,
  is_me            boolean,
  shares           boolean,
  elo              integer,
  pvp_games        integer,
  xp_total         integer,
  xp_week          integer,
  added_today      integer,
  reviewed_today   integer,
  words_learned    integer,
  kanji_learned    integer,
  recent_kanji     text[],
  active_days_week integer
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
  return query
  with people as (
    select v_me as id
    union
    select case when f.requester_id = v_me then f.addressee_id else f.requester_id end
    from public.friendships f
    where f.status = 'accepted' and v_me in (f.requester_id, f.addressee_id)
  ),
  base as (
    select p.id, pr.handle, pr.name, pr.image,
           (p.id = v_me) as me,
           (p.id = v_me or coalesce(pr.share_activity, true)) as visible,
           public.srs_day_start(now(), prefs.tz, prefs.cutoff) as day_start
    from people p
    left join public.profiles pr on pr.id = p.id
    cross join lateral public.srs_prefs(p.id) prefs
  )
  select
    b.id,
    b.handle,
    b.name,
    b.image,
    b.me,
    b.visible,
    case when b.visible then coalesce(r.elo, 1000) end,
    case when b.visible then coalesce(r.games, 0) end,
    case when b.visible then public.user_xp(b.id) end,
    case when b.visible then public.user_xp(b.id, now() - interval '7 days') end,
    case when b.visible then (
      select count(*)::int from public.words w
      where w.user_id = b.id and not w.deleted and w.date_added >= b.day_start) end,
    case when b.visible then (
      select count(*)::int from public.review_log l
      where l.user_id = b.id and not l.undone and l.source in ('review', 'quiz')
        and l.reviewed_at >= b.day_start) end,
    case when b.visible then (
      select count(*)::int from public.cards c
      join public.words w on w.id = c.word_id and not w.deleted
      where c.user_id = b.id and c.state = 'review') end,
    case when b.visible then (
      select count(*)::int from public.learned_kanji k where k.user_id = b.id) end,
    case when b.visible then (
      select array_agg(k.kanji order by k.learned_at desc)
      from (select kanji, learned_at from public.learned_kanji
            where learned_kanji.user_id = b.id
            order by learned_at desc limit 8) k) end,
    case when b.visible then (
      select count(distinct (l.reviewed_at at time zone 'UTC')::date)::int
      from public.review_log l
      where l.user_id = b.id and not l.undone
        and l.reviewed_at >= now() - interval '7 days') end
  from base b
  left join public.player_ratings r on r.user_id = b.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------
-- Tables: read through RLS; learned_kanji also writable for your own rows.
-- friendships and player_ratings have no write grant — functions only.

grant select on public.friendships    to authenticated;
grant select on public.player_ratings to authenticated;
grant select, insert, delete on public.learned_kanji to authenticated;

grant execute on function public.concede_match(uuid)                   to authenticated;
grant execute on function public.send_friend_request(text)             to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.remove_friend(uuid)                   to authenticated;
grant execute on function public.friend_requests()                     to authenticated;
grant execute on function public.friend_overview()                     to authenticated;

-- user_xp reads any user's history, so it is NOT exposed directly — only
-- through friend_overview, which decides whose numbers you may see.
revoke execute on function public.user_xp(uuid, timestamptz) from public;
revoke execute on function public.user_xp(uuid, timestamptz) from authenticated;

-- are_friends is a building block for the functions above, not an endpoint:
-- callable directly it would answer "are these two people friends?" about
-- anyone.
revoke execute on function public.are_friends(uuid, uuid) from public;
revoke execute on function public.are_friends(uuid, uuid) from authenticated;
