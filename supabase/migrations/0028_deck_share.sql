-- 0028 — public deck links.
--
-- An owner can turn on a link for one deck. Anyone holding the link — signed
-- in or not — can see that deck's words and play a trial review on the web
-- (/share/<token>); nothing they do is saved. A signed-in visitor can copy
-- the deck into their own library.
--
-- What a link exposes, and only through shared_deck():
--   * the deck's name and its live words: term, reading, meaning, meaning_mn;
--   * no owner (no user id, name, email or handle), no word ids, no SRS
--     state, no audio paths, no other deck.
-- RLS on decks/words is unchanged: signed-out visitors still cannot read any
-- table directly. The token is 128 random bits; turning the link off clears
-- it, and turning it on again issues a new one, so old links die.
--
-- Also share_today(): the caller's own words recalled today (by the SRS day,
-- so a 1am session still counts as "today"), for the story-card image.
--
-- Safe to re-run.

alter table public.decks add column if not exists share_token text;
create unique index if not exists decks_share_token_idx
  on public.decks (share_token) where share_token is not null;

-- ---------------------------------------------------------------------------
-- 1. Owner: turn the link on (returns the token) or off (returns null)
-- ---------------------------------------------------------------------------

drop function if exists public.set_deck_share(uuid, boolean);
create function public.set_deck_share(p_deck_id uuid, p_on boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;

  update public.decks
  set share_token = case
        when not p_on then null
        else coalesce(share_token, replace(gen_random_uuid()::text, '-', ''))
      end
  where id = p_deck_id and user_id = auth.uid() and not deleted
  returning share_token into v_token;

  if not found then raise exception 'deck not found'; end if;
  return v_token;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Anyone with the link: the deck's words
-- ---------------------------------------------------------------------------

drop function if exists public.shared_deck(text);
create function public.shared_deck(p_token text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'name', d.name,
    'words', coalesce((
      select jsonb_agg(jsonb_build_object(
               'term', w.term,
               'reading', w.reading,
               'meaning', w.meaning,
               'meaning_mn', w.meaning_mn
             ) order by w.date_added, w.term)
      from (
        select term, reading, meaning, meaning_mn, date_added
        from public.words
        where deck_id = d.id and not deleted
        order by date_added, term
        limit 500  -- plenty for a trial; bounds what an anonymous caller gets
      ) w
    ), '[]'::jsonb)
  )
  from public.decks d
  where p_token is not null
    and length(p_token) = 32
    and d.share_token = p_token
    and not d.deleted;
$$;

-- ---------------------------------------------------------------------------
-- 3. Signed-in visitor: copy the shared deck into their own library
-- ---------------------------------------------------------------------------

drop function if exists public.copy_shared_deck(text);
create function public.copy_shared_deck(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me     uuid := auth.uid();
  v_source public.decks%rowtype;
  v_new    uuid;
begin
  if v_me is null then raise exception 'not signed in'; end if;

  select * into v_source from public.decks
  where p_token is not null and share_token = p_token and not deleted;
  if not found then raise exception 'link not found'; end if;

  -- A fresh deck of the caller's, unfiled. The words trigger
  -- (words_create_default_card) gives every copied word a new card, so the
  -- copy starts unscheduled — the owner's review history never travels.
  insert into public.decks (user_id, name)
  values (v_me, v_source.name)
  returning id into v_new;

  insert into public.words (deck_id, user_id, term, reading, meaning, meaning_mn)
  select v_new, v_me, w.term, w.reading, w.meaning, w.meaning_mn
  from (
    select term, reading, meaning, meaning_mn, date_added
    from public.words
    where deck_id = v_source.id and not deleted
    order by date_added, term
    limit 500
  ) w
  order by w.date_added, w.term;

  return v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The caller's day, for a shareable story card
-- ---------------------------------------------------------------------------
-- Words answered right today (not "again", not undone, not PvP guesses),
-- newest first, plus today's totals. Security invoker: RLS scopes every read
-- to the caller.

drop function if exists public.share_today(integer);
create function public.share_today(p_limit integer default 12)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with prefs as (
    select public.srs_day_start(now(), p.tz, p.cutoff) as day_start
    from public.srs_prefs(auth.uid()) p
  ),
  today as (
    select r.word_id, r.rating, r.reviewed_at
    from public.review_log r, prefs
    where r.user_id = auth.uid()
      and r.reviewed_at >= prefs.day_start
      and not r.undone
      and r.source <> 'battle'
  ),
  recalled as (
    select word_id, max(reviewed_at) as last_at
    from today where rating <> 'again'
    group by word_id
  )
  select jsonb_build_object(
    'day', public.current_srs_day(),
    'answers', (select count(*) from today),
    'recalled', (select count(*) from recalled),
    'added', (select count(*) from public.words w, prefs
              where w.user_id = auth.uid() and not w.deleted
                and w.date_added >= prefs.day_start),
    'words', coalesce((
      select jsonb_agg(jsonb_build_object(
               'term', x.term, 'reading', x.reading,
               'meaning', x.meaning, 'meaning_mn', x.meaning_mn
             ) order by x.last_at desc)
      from (
        select w.term, w.reading, w.meaning, w.meaning_mn, rc.last_at
        from recalled rc join public.words w on w.id = rc.word_id
        where not w.deleted
        order by rc.last_at desc
        limit least(greatest(coalesce(p_limit, 12), 1), 50)
      ) x
    ), '[]'::jsonb)
  );
$$;

revoke execute on function public.set_deck_share(uuid, boolean) from public;
revoke execute on function public.shared_deck(text)             from public;
revoke execute on function public.copy_shared_deck(text)        from public;
-- Supabase grants anon EXECUTE on new public functions by default; the two
-- owner/copy functions check auth.uid() anyway, but say it plainly.
revoke execute on function public.set_deck_share(uuid, boolean) from anon;
revoke execute on function public.copy_shared_deck(text)        from anon;
grant execute on function public.set_deck_share(uuid, boolean) to authenticated;
grant execute on function public.shared_deck(text)             to anon, authenticated;
grant execute on function public.copy_shared_deck(text)        to authenticated;
revoke execute on function public.share_today(integer)          from public;
revoke execute on function public.share_today(integer)          from anon;
grant execute on function public.share_today(integer)          to authenticated;
