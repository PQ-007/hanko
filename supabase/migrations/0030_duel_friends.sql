-- 0030 — duels between friends: invites, rematch, and one shared question set.
--
-- What this adds to 0020/0026:
--
--  1. INVITES. A friend can be challenged directly (`invite_to_duel`) instead
--     of by reading a four-letter code aloud. The invite is an ordinary lobby
--     row with `invited_id` set; the invited friend sees it (`duel_invites`),
--     and accepts (`accept_duel_invite`) or declines.
--
--  2. REMATCH. `duel_rematch(match)` is the "again" button. It is idempotent
--     and symmetric: the first of the two players to press it creates the
--     invite, and the second one pressing it accepts that invite and the
--     match starts — so both pressing at once is not a race, it is a start.
--
--  3. THE SAME QUESTIONS FOR BOTH PLAYERS. Until now each client drew its own
--     words from its own library, so the two players were never answering the
--     same thing. When a match starts the server now plans all of its
--     questions once (`duel_plan_questions`) and stores them on the match;
--     both clients read that. Words both players have, with the same meaning,
--     come first; any shortfall is filled from each library in turn, so
--     neither side is quizzed only on the other's vocabulary. The options are
--     drawn from both libraries too.
--
--     The question set (answer included) is readable by both participants.
--     That costs nothing: clients already report their own `correct`, so the
--     answer was never a secret from a client willing to lie, and the server's
--     clamps (0020) are what bound the damage a lie buys.
--
--  4. WHO AM I FIGHTING. `duel_opponent(match)` returns the other player's
--     handle (always) and name/picture (friends only), matching 0027's rule
--     that a stranger sees a handle and nothing else.
--
-- Safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Columns, index, visibility
-- ---------------------------------------------------------------------------

alter table public.matches
  add column if not exists invited_id uuid references auth.users on delete cascade,
  add column if not exists rematch_of uuid references public.matches on delete set null,
  -- [{ term, reading, options: [text × 4], answer: 0–3 }, …], set at start.
  add column if not exists questions  jsonb;

create index if not exists matches_invited_idx
  on public.matches (invited_id) where status = 'lobby';
create index if not exists matches_rematch_idx
  on public.matches (rematch_of) where rematch_of is not null;

-- The invited friend must be able to read the lobby they were invited to.
drop policy if exists matches_select on public.matches;
create policy matches_select on public.matches for select
  using (host_id = auth.uid() or guest_id = auth.uid() or invited_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Planning the questions
-- ---------------------------------------------------------------------------

-- Internal: called from the start functions below, never by a client.
--
-- A word is "shared" when both players have the same term with the same
-- meaning text — then the question means the same thing to both of them.
-- (Same term, different meaning is treated as two different words.)
drop function if exists public.duel_plan_questions(uuid, uuid, integer);
create function public.duel_plan_questions(p_a uuid, p_b uuid, p_n integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_out   jsonb := '[]'::jsonb;
  v_q     record;
  v_wrong text[];
  v_opts  text[];
begin
  create temp table if not exists _duel_words (
    owner uuid, term text, reading text, meaning text
  ) on commit drop;
  truncate _duel_words;

  insert into _duel_words
  select distinct on (w.user_id, w.term)
         w.user_id, w.term, w.reading,
         coalesce(nullif(btrim(w.meaning_mn), ''), nullif(btrim(w.meaning), ''))
  from public.words w
  where w.user_id in (p_a, p_b) and not w.deleted and btrim(w.term) <> ''
    and coalesce(nullif(btrim(w.meaning_mn), ''), nullif(btrim(w.meaning), '')) is not null
  order by w.user_id, w.term, w.date_added desc;

  for v_q in
    with cand as (
      -- Tier 0: both players have it, same meaning.
      select a.term, a.reading, a.meaning, 0 as tier, 0 as rk
      from _duel_words a
      join _duel_words b on b.owner = p_b and b.term = a.term and b.meaning = a.meaning
      where a.owner = p_a
      union all
      -- Tier 1: everything else, taken from each library in turn (A1, B1, A2, …)
      select x.term, x.reading, x.meaning, 1,
             row_number() over (partition by x.owner order by random())::int
      from _duel_words x
      where not exists (
        select 1 from _duel_words y
        where y.owner <> x.owner and y.term = x.term and y.meaning = x.meaning
      )
    ),
    uniq as (
      select distinct on (term) term, reading, meaning, tier, rk
      from cand order by term, tier, rk
    )
    select term, reading, meaning from uniq
    order by tier, rk, random()
    limit greatest(p_n, 1)
  loop
    select array_agg(m) into v_wrong from (
      select d.meaning as m from _duel_words d
      where d.meaning <> v_q.meaning
      group by d.meaning
      order by random() limit 3
    ) s;
    continue when v_wrong is null or cardinality(v_wrong) < 3;

    select array_agg(o order by random()) into v_opts
    from unnest(array[v_q.meaning] || v_wrong) o;

    v_out := v_out || jsonb_build_object(
      'term', v_q.term,
      'reading', v_q.reading,
      'options', to_jsonb(v_opts),
      'answer', array_position(v_opts, v_q.meaning) - 1
    );
  end loop;

  -- The order the rounds are played in: random, not "shared words first".
  select coalesce(jsonb_agg(e order by random()), '[]'::jsonb) into v_out
  from jsonb_array_elements(v_out) e;
  return v_out;
end;
$$;

-- Starts a lobby for [p_guest]: the one place a match becomes active.
drop function if exists public.duel_start(uuid, uuid, text);
create function public.duel_start(p_match_id uuid, p_guest uuid, p_character text)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches;
begin
  update public.matches m set
    guest_id          = p_guest,
    guest_character   = coalesce(p_character, 'knight'),
    guest_baseline_ms = public.response_baseline_for(p_guest),
    status            = 'active',
    started_at        = now(),
    -- Burn the code on start: a lobby link shared in a group chat must not
    -- still resolve to anything an hour later.
    join_code         = null,
    questions         = public.duel_plan_questions(m.host_id, p_guest, m.round_count)
  where m.id = p_match_id
  returning * into v_match;
  return v_match;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Joining by code (0020), now through duel_start
-- ---------------------------------------------------------------------------

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
  -- An invitation is for one person.
  if v_match.invited_id is not null and v_match.invited_id <> auth.uid() then
    raise exception 'match is full';
  end if;

  return public.duel_start(v_match.id, auth.uid(), p_character);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Inviting a friend
-- ---------------------------------------------------------------------------

drop function if exists public.invite_to_duel(uuid, text);
create function public.invite_to_duel(p_friend uuid, p_character text default 'knight')
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_match public.matches;
begin
  if v_me is null then raise exception 'not signed in'; end if;
  if p_friend is null or p_friend = v_me then raise exception 'not a friend'; end if;
  if not public.are_friends(v_me, p_friend) then raise exception 'not a friend'; end if;

  -- Pressing "challenge" twice is the same challenge, not two lobbies.
  select * into v_match from public.matches
  where host_id = v_me and invited_id = p_friend and status = 'lobby'
    and created_at > now() - interval '10 minutes'
  order by created_at desc limit 1;
  if found then return v_match; end if;

  insert into public.matches (join_code, host_id, invited_id, host_character, host_baseline_ms)
  values (null, v_me, p_friend, coalesce(p_character, 'knight'),
          public.response_baseline_for(v_me))
  returning * into v_match;
  return v_match;
end;
$$;

-- Open invitations to me — a friend's challenge, or a rematch — from the last
-- ten minutes (an invitation nobody answered is not still a live offer).
drop function if exists public.duel_invites();
create function public.duel_invites()
returns table (
  match_id   uuid,
  host_id    uuid,
  host_name  text,
  host_handle text,
  host_image text,
  rematch    boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, m.host_id, pr.name, pr.handle, pr.image,
         m.rematch_of is not null, m.created_at
  from public.matches m
  left join public.profiles pr on pr.id = m.host_id
  where m.invited_id = auth.uid()
    and m.status = 'lobby'
    and m.guest_id is null
    and m.created_at > now() - interval '10 minutes'
  order by m.created_at desc;
$$;

drop function if exists public.accept_duel_invite(uuid, text);
create function public.accept_duel_invite(p_match_id uuid, p_character text default 'knight')
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into v_match from public.matches
  where id = p_match_id and invited_id = auth.uid()
  for update;
  if not found then raise exception 'no such invitation'; end if;
  if v_match.status <> 'lobby' or v_match.guest_id is not null then
    raise exception 'match already started';
  end if;
  return public.duel_start(v_match.id, auth.uid(), p_character);
end;
$$;

drop function if exists public.decline_duel_invite(uuid);
create function public.decline_duel_invite(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A declined invite is a lobby nobody joined: abandoned, no guest, so the
  -- rating trigger (0026) ignores it.
  update public.matches set status = 'abandoned', finished_at = now()
  where id = p_match_id and invited_id = auth.uid()
    and status = 'lobby' and guest_id is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Rematch — the "again" button
-- ---------------------------------------------------------------------------

-- Idempotent and symmetric. Whoever presses first creates the invitation; the
-- other pressing it (or accepting the prompt) starts the match. Pressing it
-- twice yourself returns the same waiting lobby. The original match row is
-- locked first, so two players pressing in the same instant serialise: one
-- creates, the other then finds it and starts.
drop function if exists public.duel_rematch(uuid, text);
create function public.duel_rematch(p_match_id uuid, p_character text default 'knight')
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_old   public.matches;
  v_next  public.matches;
  v_other uuid;
begin
  if v_me is null then raise exception 'not signed in'; end if;

  select * into v_old from public.matches
  where id = p_match_id and (host_id = v_me or guest_id = v_me)
    and guest_id is not null and status in ('finished', 'abandoned')
  for update;
  if not found then raise exception 'no such finished match'; end if;
  v_other := case when v_old.host_id = v_me then v_old.guest_id else v_old.host_id end;

  select * into v_next from public.matches
  where rematch_of = v_old.id and status in ('lobby', 'active')
  order by created_at desc limit 1
  for update;

  if found then
    if v_next.status = 'active' or v_next.host_id = v_me then
      return v_next;                 -- already running, or my own request
    end if;
    return public.duel_start(v_next.id, v_me, p_character);   -- theirs: accept
  end if;

  insert into public.matches
    (join_code, host_id, invited_id, rematch_of, host_character, host_baseline_ms)
  values (null, v_me, v_other, v_old.id, coalesce(p_character, 'knight'),
          public.response_baseline_for(v_me))
  returning * into v_next;
  return v_next;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Who is across the table
-- ---------------------------------------------------------------------------

drop function if exists public.duel_opponent(uuid);
create function public.duel_opponent(p_match_id uuid)
returns table (
  opponent_id uuid,
  handle      text,
  name        text,
  image       text,
  is_friend   boolean,
  elo         integer,
  games       integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_match public.matches;
  v_other uuid;
  v_friend boolean;
begin
  select * into v_match from public.matches
  where id = p_match_id and (host_id = v_me or guest_id = v_me);
  if not found then raise exception 'not your match'; end if;
  v_other := case when v_match.host_id = v_me then v_match.guest_id else v_match.host_id end;
  if v_other is null then return; end if;
  v_friend := public.are_friends(v_me, v_other);

  return query
  select v_other, pr.handle,
         case when v_friend then pr.name end,
         case when v_friend then pr.image end,
         v_friend,
         coalesce(r.elo, 1000), coalesce(r.games, 0)
  from (select 1) one
  left join public.profiles pr on pr.id = v_other
  left join public.player_ratings r on r.user_id = v_other;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Friends, cheaply
-- ---------------------------------------------------------------------------

-- Just who your friends are, to pick someone to challenge. friend_overview()
-- (0026) also computes every friend's XP and streak, which is far too much for
-- a list of names.
drop function if exists public.my_friends();
create function public.my_friends()
returns table (user_id uuid, handle text, name text, image text)
language sql
stable
security definer
set search_path = public
as $$
  select pr.id, pr.handle, pr.name, pr.image
  from public.friendships f
  join public.profiles pr
    on pr.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where f.status = 'accepted' and auth.uid() in (f.requester_id, f.addressee_id)
  order by lower(coalesce(pr.name, pr.handle, ''));
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------

-- The planners are building blocks, not endpoints: callable directly,
-- duel_plan_questions would read any two users' vocabularies.
revoke execute on function public.duel_plan_questions(uuid, uuid, integer) from public, authenticated;
revoke execute on function public.duel_start(uuid, uuid, text)             from public, authenticated;

grant execute on function public.join_match(text, text)              to authenticated;
grant execute on function public.invite_to_duel(uuid, text)          to authenticated;
grant execute on function public.duel_invites()                      to authenticated;
grant execute on function public.accept_duel_invite(uuid, text)      to authenticated;
grant execute on function public.decline_duel_invite(uuid)           to authenticated;
grant execute on function public.duel_rematch(uuid, text)            to authenticated;
grant execute on function public.duel_opponent(uuid)                 to authenticated;
grant execute on function public.my_friends()                        to authenticated;
