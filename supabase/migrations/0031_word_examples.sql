-- One example sentence per word, with its English and Mongolian translations.
--
-- Stored on the word (the note), not the card: every card of a word shares the
-- same sentence. Filled in when a word is added — suggested from Tatoeba,
-- editable — and shown on the back of a review card. All three are optional;
-- a word with no sentence behaves exactly as before.
--
-- The extension never sends these columns, and PostgREST's merge-duplicates
-- upsert leaves absent columns untouched (CLAUDE.md 0.7), so its sync can't
-- wipe a sentence added on the web or the phone.
--
-- Shared deck links show and copy them too (end of file).
--
-- The queue RPCs gain the three columns at the end of their row so the review
-- screens get them without a second fetch. Appended, never inserted: clients
-- read rows by name, and older clients simply ignore the extra keys.

alter table public.words add column if not exists example_ja text;
alter table public.words add column if not exists example_en text;
alter table public.words add column if not exists example_mn text;

-- A sentence, not an essay; also keeps a hostile client from parking
-- megabytes in a row every queue fetch then carries.
alter table public.words drop constraint if exists words_example_len;
alter table public.words add constraint words_example_len check (
  coalesce(char_length(example_ja), 0) <= 300
  and coalesce(char_length(example_en), 0) <= 500
  and coalesce(char_length(example_mn), 0) <= 500
);

-- ---------------------------------------------------------------------------
-- review_queue: 0021's body unchanged, plus the example columns.
-- ---------------------------------------------------------------------------
drop function if exists public.review_queue(uuid, integer);

create function public.review_queue(
  p_deck_id uuid    default null,
  p_limit   integer default 60
) returns table (
  card_id       uuid,
  word_id       uuid,
  deck_id       uuid,
  template      text,
  state         text,
  learning_step smallint,
  due_at        timestamptz,
  interval_days integer,
  repetitions   integer,
  ease_factor   numeric,
  stability     double precision,
  difficulty    double precision,
  last_reviewed_at timestamptz,
  term          text,
  reading       text,
  meaning       text,
  meaning_mn    text,
  audio_path    text,
  example_ja    text,
  example_en    text,
  example_mn    text
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
    and source in ('review', 'quiz')
    and undone = false
    and reviewed_at >= v_day_start;

  return query
  with due as (
    select
      c.id, c.word_id, c.template, c.state, c.learning_step, c.due_at,
      c.interval_days, c.repetitions, c.ease_factor,
      c.stability, c.difficulty, c.last_reviewed_at,
      w.deck_id, w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path,
      w.example_ja, w.example_en, w.example_mn
    from public.cards c
    join public.words w on w.id = c.word_id
    where c.user_id = v_user
      and c.suspended = false
      and w.deleted = false
      and (p_deck_id is null or w.deck_id = p_deck_id)
      and c.due_at <= now()
  ),
  reviews as (
    select * from due where due.state <> 'new'
    order by due.due_at
    limit greatest(v_rev_cap - v_rev_done, 0)
  ),
  news as (
    select * from due where due.state = 'new'
    order by due.due_at
    limit greatest(v_new_cap - v_new_done, 0)
  )
  select
    q.id, q.word_id, q.deck_id, q.template, q.state, q.learning_step, q.due_at,
    q.interval_days, q.repetitions, q.ease_factor,
    q.stability, q.difficulty, q.last_reviewed_at,
    q.term, q.reading, q.meaning, q.meaning_mn, q.audio_path,
    q.example_ja, q.example_en, q.example_mn
  from (select * from reviews union all select * from news) q
  order by (q.state = 'new'), q.due_at
  limit p_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- practice_cards: 0017's body unchanged, plus the example columns.
-- ---------------------------------------------------------------------------
drop function if exists public.practice_cards(uuid, integer);

create function public.practice_cards(
  p_deck_id uuid    default null,
  p_limit   integer default 60
) returns table (
  card_id       uuid,
  word_id       uuid,
  deck_id       uuid,
  template      text,
  state         text,
  learning_step smallint,
  due_at        timestamptz,
  interval_days integer,
  repetitions   integer,
  ease_factor   numeric,
  term          text,
  reading       text,
  meaning       text,
  meaning_mn    text,
  audio_path    text,
  example_ja    text,
  example_en    text,
  example_mn    text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    c.id, c.word_id, w.deck_id, c.template, c.state, c.learning_step, c.due_at,
    c.interval_days, c.repetitions, c.ease_factor,
    w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path,
    w.example_ja, w.example_en, w.example_mn
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = auth.uid()
    and c.suspended = false
    and w.deleted = false
    and (p_deck_id is null or w.deck_id = p_deck_id)
  order by random()
  limit p_limit;
$$;

-- ---------------------------------------------------------------------------
-- leech_cards: 0014's body unchanged, plus the example columns.
-- ---------------------------------------------------------------------------
drop function if exists public.leech_cards(uuid, integer);

create function public.leech_cards(
  p_deck_id uuid    default null,
  p_limit   integer default 30
) returns table (
  card_id       uuid,
  word_id       uuid,
  deck_id       uuid,
  template      text,
  state         text,
  learning_step smallint,
  due_at        timestamptz,
  interval_days integer,
  repetitions   integer,
  ease_factor   numeric,
  term          text,
  reading       text,
  meaning       text,
  meaning_mn    text,
  audio_path    text,
  example_ja    text,
  example_en    text,
  example_mn    text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    c.id, c.word_id, w.deck_id, c.template, c.state, c.learning_step, c.due_at,
    c.interval_days, c.repetitions, c.ease_factor,
    w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path,
    w.example_ja, w.example_en, w.example_mn
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = auth.uid()
    and c.suspended = false
    and w.deleted = false
    and c.lapses >= 4
    and (p_deck_id is null or w.deck_id = p_deck_id)
  order by c.lapses desc, c.due_at
  limit p_limit;
$$;

-- ---------------------------------------------------------------------------
-- Shared deck links (0028) carry the sentences too: shown on the share page,
-- and copied with the deck. 0028's bodies otherwise unchanged — still no
-- owner, ids, SRS state or audio paths.
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
               'meaning_mn', w.meaning_mn,
               'example_ja', w.example_ja,
               'example_en', w.example_en,
               'example_mn', w.example_mn
             ) order by w.date_added, w.term)
      from (
        select term, reading, meaning, meaning_mn, example_ja, example_en, example_mn, date_added
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
    and d.share_expires_at > now()
    and not d.deleted;
$$;

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
  where p_token is not null and share_token = p_token
    and share_expires_at > now() and not deleted;
  if not found then raise exception 'link not found'; end if;

  insert into public.decks (user_id, name)
  values (v_me, v_source.name)
  returning id into v_new;

  insert into public.words (deck_id, user_id, term, reading, meaning, meaning_mn,
                            example_ja, example_en, example_mn)
  select v_new, v_me, w.term, w.reading, w.meaning, w.meaning_mn,
         w.example_ja, w.example_en, w.example_mn
  from (
    select term, reading, meaning, meaning_mn, example_ja, example_en, example_mn, date_added
    from public.words
    where deck_id = v_source.id and not deleted
    order by date_added, term
    limit 500
  ) w
  order by w.date_added, w.term;

  return v_new;
end;
$$;

-- Dropping a function drops its grants: 0028's, restated.
revoke execute on function public.shared_deck(text)      from public;
revoke execute on function public.copy_shared_deck(text) from public;
revoke execute on function public.copy_shared_deck(text) from anon;
grant execute on function public.shared_deck(text)      to anon, authenticated;
grant execute on function public.copy_shared_deck(text) to authenticated;
