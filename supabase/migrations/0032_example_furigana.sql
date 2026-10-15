-- The reading of an example sentence (0031), for furigana over its kanji.
--
-- Stored as Tatoeba gives it, which is where every suggested sentence comes
-- from: "[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。" — a bracket per word,
-- one reading per kanji when they split cleanly ("[勉強|べん|きょう]"), else one
-- for the whole word. No tokenizer needed, on the device or anywhere else.
--
-- It describes example_ja exactly: clients show it only while its plain text
-- (the brackets' bases joined) equals example_ja, and drop it on save once
-- the user edits the sentence. A sentence the user wrote has none and shows
-- without furigana.
--
-- The queue and share functions return it, appended after example_mn; their
-- bodies are otherwise 0031's.

alter table public.words add column if not exists example_furigana text;

alter table public.words drop constraint if exists words_example_furigana_len;
alter table public.words add constraint words_example_furigana_len check (
  coalesce(char_length(example_furigana), 0) <= 900
);

-- ---------------------------------------------------------------------------
-- review_queue: 0031's, plus example_furigana.
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
  example_mn    text,
  example_furigana text
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
      w.example_ja, w.example_en, w.example_mn, w.example_furigana
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
    q.example_ja, q.example_en, q.example_mn, q.example_furigana
  from (select * from reviews union all select * from news) q
  order by (q.state = 'new'), q.due_at
  limit p_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- practice_cards: 0031's, plus example_furigana.
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
  example_mn    text,
  example_furigana text
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
    w.example_ja, w.example_en, w.example_mn, w.example_furigana
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
-- leech_cards: 0031's, plus example_furigana.
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
  example_mn    text,
  example_furigana text
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
    w.example_ja, w.example_en, w.example_mn, w.example_furigana
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
               'example_mn', w.example_mn,
               'example_furigana', w.example_furigana
             ) order by w.date_added, w.term)
      from (
        select term, reading, meaning, meaning_mn, example_ja, example_en, example_mn, example_furigana, date_added
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
                            example_ja, example_en, example_mn, example_furigana)
  select v_new, v_me, w.term, w.reading, w.meaning, w.meaning_mn,
         w.example_ja, w.example_en, w.example_mn, w.example_furigana
  from (
    select term, reading, meaning, meaning_mn, example_ja, example_en, example_mn, example_furigana, date_added
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
