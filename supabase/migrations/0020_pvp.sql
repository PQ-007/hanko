-- PvP duels — Найзтайгаа тулах. See PVP.md for the plan this implements.
--
-- Four things live here:
--   1. response_baseline()  — each player's own median response time, which is
--      what duel damage is scaled against. This is the payoff for Phase 0.4
--      insisting review_log.duration_ms land before mobile rather than
--      alongside battle mode: there is real history to take a median of.
--   2. The match tables, RLS-scoped to the two participants.
--   3. duel_damage() — a mirror of web/.../duel/_lib/duel.ts. Every constant
--      below is duplicated from that file ON PURPOSE and must be kept in step
--      with it; see the golden-fixture note above the function.
--   4. The round lifecycle: begin_round / submit_round_answer / resolve_round,
--      all idempotent, first writer wins.
--
-- What is NOT here: any change to review_card(). PvP answers are logged with
-- source='battle', which 0018 already routes down the log-only branch — the
-- card comes back untouched. That value was reserved for this mode and the
-- reservation is enforced server-side, so a client bug cannot schedule on a
-- three-second guess.
--
-- Safe to re-run: every policy and trigger is dropped first, and every
-- table-returning or row-returning function is dropped before creation
-- (create or replace cannot change a function's return row type).

-- ---------------------------------------------------------------------------
-- 1. The player's own response baseline
-- ---------------------------------------------------------------------------

-- Median, not mean: one answer where the user walked away mid-review is enough
-- to drag a mean into uselessness, and duration_ms has no upper bound.
--
-- Returns NULL below MIN_SAMPLES rather than a number computed from a handful
-- of reviews. The client falls back to a constant for null (duel.ts's
-- FALLBACK_BASELINE_MS) — a baseline derived from three answers is noise
-- dressed up as personalisation, and it would decide real matches.
create or replace function public.response_baseline()
returns integer
language sql
stable
security invoker
set search_path = public
as $$
  select case
           when count(*) < 20 then null
           else percentile_cont(0.5) within group (order by l.duration_ms)::integer
         end
  from public.review_log l
  where l.user_id = auth.uid()
    and l.source in ('review', 'quiz')   -- real recall only; drills and duels are excluded
    and l.undone = false
    and l.duration_ms between 400 and 30000  -- discards mis-taps and walk-aways
    and l.reviewed_at >= now() - interval '90 days';
$$;

-- The same median for an arbitrary user. response_baseline() reads auth.uid()
-- and so cannot answer for an opponent; a match needs both.
create or replace function public.response_baseline_for(p_user uuid)
returns integer
language sql
stable
security invoker
set search_path = public
as $$
  select case
           when count(*) < 20 then null
           else percentile_cont(0.5) within group (order by l.duration_ms)::integer
         end
  from public.review_log l
  where l.user_id = p_user
    and l.source in ('review', 'quiz')
    and l.undone = false
    and l.duration_ms between 400 and 30000
    and l.reviewed_at >= now() - interval '90 days';
$$;

-- ---------------------------------------------------------------------------
-- 2. Match tables
-- ---------------------------------------------------------------------------

create table if not exists public.matches (
  id             uuid primary key default gen_random_uuid(),
  -- Nulled the moment the match starts, so a screenshot of a lobby is not a
  -- permanent back door into someone's game.
  join_code      text unique,
  host_id        uuid not null references auth.users on delete cascade,
  guest_id       uuid references auth.users on delete cascade,
  host_character text not null default 'knight',
  guest_character text,
  -- Each player's median response time, FROZEN at the moment they enter the
  -- match rather than recomputed per round. Two reasons, both load-bearing:
  -- a review finished mid-match would otherwise shift the baseline and make
  -- the client's predicted damage disagree with the server's, and RLS means a
  -- client cannot compute its opponent's median for itself — it has to be
  -- told, and both sides have to be told the same thing.
  host_baseline_ms  integer,
  guest_baseline_ms integer,
  status         text not null default 'lobby'
                   check (status in ('lobby', 'active', 'finished', 'abandoned')),
  round_count    integer not null default 12,
  -- The highest round whose damage has been applied. Rounds resolve in order,
  -- and this is what makes resolve_round idempotent.
  current_round  integer not null default 0,
  host_hp        integer not null default 100,
  guest_hp       integer not null default 100,
  winner_id      uuid references auth.users,
  created_at     timestamptz not null default now(),
  started_at     timestamptz,
  finished_at    timestamptz
);

create index if not exists matches_host_idx on public.matches (host_id);
create index if not exists matches_guest_idx on public.matches (guest_id);

create table if not exists public.match_rounds (
  match_id    uuid not null references public.matches on delete cascade,
  round_no    integer not null,
  -- Server-issued, and the only clock either client is allowed to trust.
  starts_at   timestamptz not null default now(),
  duration_ms integer not null,
  primary key (match_id, round_no)
);

create table if not exists public.match_answers (
  match_id          uuid not null references public.matches on delete cascade,
  round_no          integer not null,
  user_id           uuid not null references auth.users on delete cascade,
  card_id           uuid references public.cards on delete set null,
  correct           boolean not null,
  client_elapsed_ms integer,
  -- What the server decided the answer actually took, after clamping. Damage
  -- is computed from this and never from client_elapsed_ms.
  effective_ms      integer not null,
  damage            integer not null default 0,
  answered_at       timestamptz not null default now(),
  primary key (match_id, round_no, user_id)
);

-- ---------------------------------------------------------------------------
-- 3. RLS — participants only
-- ---------------------------------------------------------------------------

alter table public.matches       enable row level security;
alter table public.match_rounds  enable row level security;
alter table public.match_answers enable row level security;

drop policy if exists matches_select on public.matches;
create policy matches_select on public.matches for select
  using (host_id = auth.uid() or guest_id = auth.uid());

-- Insert/update go through the functions below, which are the only things that
-- may set HP, status or a winner. No direct update policy exists on purpose:
-- with one, a client could simply set the opponent's HP to zero.
drop policy if exists matches_insert on public.matches;
create policy matches_insert on public.matches for insert
  with check (host_id = auth.uid());

drop policy if exists match_rounds_select on public.match_rounds;
create policy match_rounds_select on public.match_rounds for select
  using (exists (
    select 1 from public.matches m
    where m.id = match_id and (m.host_id = auth.uid() or m.guest_id = auth.uid())
  ));

-- Both players read every answer in their match — you cannot render an
-- opponent's HP without it.
drop policy if exists match_answers_select on public.match_answers;
create policy match_answers_select on public.match_answers for select
  using (exists (
    select 1 from public.matches m
    where m.id = match_id and (m.host_id = auth.uid() or m.guest_id = auth.uid())
  ));

-- ---------------------------------------------------------------------------
-- 4. Damage — the mirror of duel.ts
-- ---------------------------------------------------------------------------

-- MIRROR WARNING. Every constant here is duplicated from
-- web/src/app/decks/review/duel/_lib/duel.ts. That duplication is deliberate
-- and load-bearing (bot matches never touch the network; PvP matches must not
-- trust the client), but it is exactly the "two implementations drifting
-- unchecked" hazard CLAUDE.md's Stack section warns about.
--
-- The guard is the golden fixture at web/.../duel/_lib/duel.fixture.json:
-- duel.test.ts asserts the TypeScript against it, and the query in
-- duel_damage_fixture_check() below asserts this function against the same
-- rows. Change a number in one place and one of the two fails.
--
-- Note on rounding: JS Math.round and SQL round(numeric) both round halves
-- away from zero for positive values, and damage is always positive, so the
-- two agree without further care.
create or replace function public.duel_damage(
  p_correct     boolean,
  p_elapsed_ms  integer,
  p_baseline_ms integer,
  p_streak      integer
) returns integer
language sql
immutable
as $$
  select case
    when p_correct is not true then 0
    else round(
      8                                                    -- BASE_DAMAGE
      * least(1.6, greatest(0.6,                           -- ratio clamps
          coalesce(nullif(p_baseline_ms, 0), 4500)::numeric  -- FALLBACK_BASELINE_MS
          / greatest(350, coalesce(p_elapsed_ms, 350))::numeric  -- ELAPSED_FLOOR_MS
        ))
      * case                                               -- streak multipliers
          when p_streak >= 6 then 1.4
          when p_streak >= 3 then 1.2
          else 1
        end
    )::integer
  end;
$$;

-- Same curve as duel.ts's roundDurationMs: 5s, tightening 250ms a round to a
-- 3s floor.
create or replace function public.duel_round_duration_ms(p_round_no integer)
returns integer
language sql
immutable
as $$
  select greatest(3000, 5000 - (greatest(1, p_round_no) - 1) * 250);
$$;

-- ---------------------------------------------------------------------------
-- 5. Lobby
-- ---------------------------------------------------------------------------

-- No 0/O and no 1/I/L: these codes get read aloud and typed from a photo.
create or replace function public.duel_join_code()
returns text
language sql
volatile
as $$
  select string_agg(
    substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ',
           (floor(random() * 31) + 1)::integer, 1), '')
  from generate_series(1, 4);
$$;

drop function if exists public.create_match(text);
create function public.create_match(p_character text default 'knight')
returns public.matches
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_match public.matches;
  v_code  text;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  -- A four-character code over a 31-character alphabet is ~923k combinations
  -- against a handful of open lobbies, so a collision is a retry, not a
  -- design problem. Ten attempts before giving up.
  for i in 1..10 loop
    v_code := public.duel_join_code();
    exit when not exists (select 1 from public.matches where join_code = v_code);
    v_code := null;
  end loop;
  if v_code is null then
    raise exception 'could not allocate a join code';
  end if;

  insert into public.matches (join_code, host_id, host_character, host_baseline_ms)
  values (v_code, auth.uid(), coalesce(p_character, 'knight'),
          public.response_baseline_for(auth.uid()))
  returning * into v_match;

  return v_match;
end;
$$;

-- SECURITY DEFINER, and the only one in this migration.
--
-- It has to be: RLS scopes `matches` to its two participants, and a guest
-- looking up a code is by definition not yet one of them, so an invoker-rights
-- function would find nothing. Every check the policies would have made is
-- therefore made here by hand — an unjoinable match must fail loudly rather
-- than silently return someone else's game.
drop function if exists public.join_match(text, text);
create function public.join_match(p_code text, p_character text default 'knight')
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  select * into v_match
  from public.matches
  where join_code = upper(trim(p_code))
  for update;

  if not found then
    raise exception 'no such match';
  end if;
  if v_match.status <> 'lobby' then
    raise exception 'match already started';
  end if;
  if v_match.guest_id is not null then
    raise exception 'match is full';
  end if;
  if v_match.host_id = auth.uid() then
    raise exception 'cannot join your own match';
  end if;

  update public.matches set
    guest_id          = auth.uid(),
    guest_character   = coalesce(p_character, 'knight'),
    guest_baseline_ms = public.response_baseline_for(auth.uid()),
    status            = 'active',
    started_at      = now(),
    -- Burn the code on start. A lobby link shared in a group chat must not
    -- still resolve to anything an hour later.
    join_code       = null
  where id = v_match.id
  returning * into v_match;

  return v_match;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The round lifecycle
-- ---------------------------------------------------------------------------

-- SECURITY DEFINER, like join_match and for a related reason.
--
-- The three tables grant SELECT and nothing else, so that a client cannot
-- reach in and zero the opponent's HP. That leaves the legitimate paths
-- unable to do their job under invoker rights: this one needs INSERT, and
-- resolve_round/forfeit_match need `select ... for update`, which requires the
-- UPDATE privilege that is being withheld on purpose. Definer rights are
-- exactly the tool for "the caller may do this, but only through here".
--
-- Definer also bypasses RLS, so the participant check below is not a
-- convenience — it IS the access control, and every function in this section
-- performs it before touching anything.
--
-- Rounds are opened on demand rather than scheduled up front. A schedule laid
-- out at match start drifts: it assumes both clients render at the same moment
-- and never stall. Whichever client reaches round N first fixes its start
-- time, and the other one measures against that same server timestamp — so
-- neither client's clock is ever trusted, and a slow loader simply gets less
-- of the round rather than a round that already expired.
drop function if exists public.begin_round(uuid, integer);
create function public.begin_round(p_match_id uuid, p_round_no integer)
returns public.match_rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches;
  v_round public.match_rounds;
begin
  select * into v_match from public.matches
  where id = p_match_id and (host_id = auth.uid() or guest_id = auth.uid());
  if not found then
    raise exception 'not your match';
  end if;
  if p_round_no < 1 or p_round_no > v_match.round_count then
    raise exception 'round % out of range', p_round_no;
  end if;

  insert into public.match_rounds (match_id, round_no, duration_ms)
  values (p_match_id, p_round_no, public.duel_round_duration_ms(p_round_no))
  on conflict (match_id, round_no) do nothing;

  select * into v_round from public.match_rounds
  where match_id = p_match_id and round_no = p_round_no;
  return v_round;
end;
$$;

-- Records one player's answer. Idempotent on (match, round, player): an
-- offline retry must not overwrite the first answer with a later, slower one.
--
-- effective_ms is the anti-cheat budget in full, and deliberately no larger.
-- Both clients render the question locally, so display time is client-side
-- whatever we do; what this can honestly do is bound the damage a lie buys.
--
-- The rule is GREATEST(what the client claims, what the server's own clock saw
-- minus a latency allowance) — not least(). Least is the intuitive-looking
-- version and it is exactly backwards: under-reporting is the whole cheat
-- (faster answer, more damage), so taking the smaller of the two hands the
-- cheater their lie, and the 350ms floor then rounds it to the best value
-- obtainable. Greatest makes the server's clock a floor instead, and the
-- allowance is what keeps an honest player's network round trip from being
-- charged to their think time.
--
-- Worked: a client claiming 1ms on a round the server saw take 2000ms is
-- charged 1500ms. An honest 1200ms answer arriving 100ms later is charged
-- 1200ms. The one loser is a player on a genuinely awful connection, who is
-- billed for the excess — acceptable, because stalling only ever reduces your
-- own damage, so it is not a strategy anyone would choose.
drop function if exists public.submit_round_answer(uuid, integer, boolean, integer, uuid);
create function public.submit_round_answer(
  p_match_id          uuid,
  p_round_no          integer,
  p_correct           boolean,
  p_client_elapsed_ms integer,
  p_card_id           uuid default null
) returns public.match_answers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match     public.matches;
  v_round     public.match_rounds;
  v_answer    public.match_answers;
  v_server_ms integer;
  v_effective integer;
begin
  select * into v_match from public.matches
  where id = p_match_id and (host_id = auth.uid() or guest_id = auth.uid());
  if not found then
    raise exception 'not your match';
  end if;

  select * into v_round from public.match_rounds
  where match_id = p_match_id and round_no = p_round_no;
  if not found then
    raise exception 'round % has not started', p_round_no;
  end if;

  v_server_ms := (extract(epoch from (now() - v_round.starts_at)) * 1000)::integer;
  v_effective := greatest(
    coalesce(p_client_elapsed_ms, v_round.duration_ms),
    v_server_ms - 500   -- one-way latency allowance
  );
  v_effective := least(v_round.duration_ms, greatest(350, v_effective));

  insert into public.match_answers (
    match_id, round_no, user_id, card_id, correct, client_elapsed_ms, effective_ms
  ) values (
    p_match_id, p_round_no, auth.uid(), p_card_id,
    coalesce(p_correct, false), p_client_elapsed_ms, v_effective
  )
  on conflict (match_id, round_no, user_id) do nothing;

  select * into v_answer from public.match_answers
  where match_id = p_match_id and round_no = p_round_no and user_id = auth.uid();
  return v_answer;
end;
$$;

-- Applies one round's damage. Either client may call it — whichever arrives
-- first does the work, and the `current_round` guard makes the second call a
-- no-op rather than a double hit.
--
-- A missing answer row is a timeout: no damage, and the streak breaks. That is
-- why this is a separate function from submit_round_answer — a round where one
-- player never answers has nobody to trigger the resolution from their own
-- submission.
drop function if exists public.resolve_round(uuid, integer);
create function public.resolve_round(p_match_id uuid, p_round_no integer)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match    public.matches;
  v_round    public.match_rounds;
  v_host_ok  boolean;
  v_guest_ok boolean;
  v_host_ms  integer;
  v_guest_ms integer;
  v_host_base  integer;
  v_guest_base integer;
  v_host_streak  integer := 0;
  v_guest_streak integer := 0;
  v_host_dmg  integer;
  v_guest_dmg integer;
  v_ok boolean;
  r integer;
begin
  select * into v_match from public.matches
  where id = p_match_id and (host_id = auth.uid() or guest_id = auth.uid())
  for update;
  if not found then
    raise exception 'not your match';
  end if;

  -- Already applied (or the match is over). First writer won.
  if v_match.current_round >= p_round_no or v_match.status <> 'active' then
    return v_match;
  end if;
  -- Rounds resolve strictly in order, so a client that skipped ahead cannot
  -- apply round 7 before round 6.
  if p_round_no <> v_match.current_round + 1 then
    raise exception 'round % is not next (current %)', p_round_no, v_match.current_round;
  end if;

  select * into v_round from public.match_rounds
  where match_id = p_match_id and round_no = p_round_no;
  if not found then
    raise exception 'round % has not started', p_round_no;
  end if;

  select correct, effective_ms into v_host_ok, v_host_ms
  from public.match_answers
  where match_id = p_match_id and round_no = p_round_no and user_id = v_match.host_id;

  select correct, effective_ms into v_guest_ok, v_guest_ms
  from public.match_answers
  where match_id = p_match_id and round_no = p_round_no and user_id = v_match.guest_id;

  -- Nobody may resolve a round early: until the buzzer, a player who has
  -- answered could otherwise close the round on an opponent who is still
  -- reading it.
  if (v_host_ok is null or v_guest_ok is null)
     and now() < v_round.starts_at + make_interval(secs => v_round.duration_ms / 1000.0) then
    return v_match;
  end if;

  -- The baselines frozen when each player entered the match, NOT recomputed:
  -- both clients predict damage locally from these same two numbers (they are
  -- on the match row precisely so they can), and a median that moved mid-match
  -- would put the prediction and the server permanently at odds.
  v_host_base  := v_match.host_baseline_ms;
  v_guest_base := v_match.guest_baseline_ms;

  -- Consecutive correct answers immediately before this round. Walked backwards
  -- rather than windowed because a MISSING row (a timeout) breaks the streak
  -- too, and a window function over rows that exist cannot see the gaps.
  for r in reverse (p_round_no - 1)..1 loop
    select correct into v_ok from public.match_answers
    where match_id = p_match_id and round_no = r and user_id = v_match.host_id;
    exit when v_ok is null or v_ok = false;
    v_host_streak := v_host_streak + 1;
  end loop;

  for r in reverse (p_round_no - 1)..1 loop
    select correct into v_ok from public.match_answers
    where match_id = p_match_id and round_no = r and user_id = v_match.guest_id;
    exit when v_ok is null or v_ok = false;
    v_guest_streak := v_guest_streak + 1;
  end loop;

  v_host_dmg  := public.duel_damage(v_host_ok,  v_host_ms,  v_host_base,  v_host_streak);
  v_guest_dmg := public.duel_damage(v_guest_ok, v_guest_ms, v_guest_base, v_guest_streak);

  update public.match_answers set damage = v_host_dmg
  where match_id = p_match_id and round_no = p_round_no and user_id = v_match.host_id;
  update public.match_answers set damage = v_guest_dmg
  where match_id = p_match_id and round_no = p_round_no and user_id = v_match.guest_id;

  -- Both hits land together, which is what makes a simultaneous knockout — and
  -- therefore a draw — reachable rather than theoretical.
  update public.matches set
    host_hp       = greatest(0, host_hp - v_guest_dmg),
    guest_hp      = greatest(0, guest_hp - v_host_dmg),
    current_round = p_round_no
  where id = p_match_id
  returning * into v_match;

  if v_match.host_hp <= 0 or v_match.guest_hp <= 0
     or v_match.current_round >= v_match.round_count then
    update public.matches set
      status      = 'finished',
      finished_at = now(),
      -- Equal HP is a draw and stays NULL. Both a simultaneous knockout and a
      -- level scoreline after the final round land here.
      winner_id   = case
                      when host_hp > guest_hp then host_id
                      when guest_hp > host_hp then guest_id
                      else null
                    end
    where id = p_match_id
    returning * into v_match;
  end if;

  return v_match;
end;
$$;

-- An opponent who closes the tab must not leave the other player staring at a
-- countdown forever. The surviving client calls this; the round schedule
-- bounds how long that takes, so no background job is needed.
drop function if exists public.forfeit_match(uuid);
create function public.forfeit_match(p_match_id uuid)
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
    -- The caller is the one still here, so they win it. A lobby nobody joined
    -- has no winner to name.
    winner_id   = case when v_match.guest_id is null then null else auth.uid() end
  where id = p_match_id
  returning * into v_match;

  return v_match;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------

-- Stated explicitly rather than left to Supabase's default privileges, for the
-- same reason 0009 grants undo_review by hand: RLS decides which ROWS a caller
-- sees, and it is only reached if the role has the table privilege at all. A
-- missing grant fails as "permission denied" — which reads like an RLS bug and
-- gets debugged as one.
--
-- SELECT and nothing else on the three tables. Every write goes through the
-- lifecycle functions, which run SECURITY DEFINER and check participation
-- themselves — a direct UPDATE grant would let a client simply zero the
-- opponent's HP, and withholding it is what makes those functions the only
-- door. The one exception is INSERT on matches, which create_match needs
-- because it runs with invoker rights and the insert policy already pins
-- host_id to auth.uid().
grant select on public.matches       to authenticated;
grant select on public.match_rounds  to authenticated;
grant select on public.match_answers to authenticated;
grant insert on public.matches       to authenticated;

grant execute on function public.response_baseline()               to authenticated;
grant execute on function public.response_baseline_for(uuid)       to authenticated;
grant execute on function public.duel_damage(boolean, integer, integer, integer) to authenticated;
grant execute on function public.duel_round_duration_ms(integer)   to authenticated;
grant execute on function public.create_match(text)                to authenticated;
grant execute on function public.join_match(text, text)            to authenticated;
grant execute on function public.begin_round(uuid, integer)        to authenticated;
grant execute on function public.submit_round_answer(uuid, integer, boolean, integer, uuid) to authenticated;
grant execute on function public.resolve_round(uuid, integer)      to authenticated;
grant execute on function public.forfeit_match(uuid)               to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Realtime
-- ---------------------------------------------------------------------------

-- Without this, subscriptions connect successfully and simply never fire —
-- no error on either side. It is the single easiest thing in this file to
-- forget and the hardest to diagnose afterwards.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'matches'
  ) then
    alter publication supabase_realtime add table public.matches;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_answers'
  ) then
    alter publication supabase_realtime add table public.match_answers;
  end if;
exception
  when undefined_object then
    -- No supabase_realtime publication (a plain Postgres, e.g. the migration
    -- test harness). The tables are still correct; only live updates are
    -- unavailable.
    raise notice 'supabase_realtime publication not present, skipping';
end;
$$;
