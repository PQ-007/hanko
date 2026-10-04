-- Replace SM-2 with FSRS-5 (Free Spaced Repetition Scheduler).
--
-- FSRS models each card with two numbers instead of ease_factor + interval:
--   stability (S) — days until retrievability drops to 90%
--   difficulty (D) — inherent hardness, 1 (easy) to 10 (hard)
--
-- The forgetting curve is R(t,S) = (1 + FACTOR*t/S)^(-2) where FACTOR = 19/81.
-- The target interval for 90% retention solves to I = S * 0.2306.
--
-- Signature of review_card() is unchanged — all clients call it identically.
-- review_queue(), due_summary(), review_activity() are unchanged.
-- undo_review() is restated below to also restore stability and difficulty.
--
-- This file supersedes 0009 and 0018 for review_card() and undo_review().
-- Safe to re-run: create-or-replace and if-not-exists guards throughout.

-- ---------------------------------------------------------------------------
-- Schema changes
-- ---------------------------------------------------------------------------
alter table public.cards
  add column if not exists stability  double precision,
  add column if not exists difficulty double precision;

-- Backfill existing review cards. New/learning/relearning cards get null and
-- receive proper values when they first graduate to review state.
--
-- S = interval_days / 0.2306 (inverse of the 90%-retention interval formula),
-- damped by repetition count. A card with only 1-2 successful reviews hasn't
-- earned the same confidence as one with 5+, even at the same interval_days —
-- SM-2's interval already assumed ~90% retention with far less evidence than
-- FSRS expects, so trusting it at face value overstates how well-known the
-- card is and inflates the very first FSRS interval. Damping ramps from 0.45
-- at 1 repetition to 1.0 (full trust) at 5+.
-- D = rough approximation from ease_factor: higher EF → lower D.
update public.cards
set
  stability  = greatest(0.5, (interval_days / 0.2306) * least(1.0, 0.3 + repetitions * 0.15)),
  difficulty = greatest(1.0, least(10.0, 11.0 - ease_factor * 2.0))
where state = 'review'
  and stability is null
  and interval_days > 0;

-- ---------------------------------------------------------------------------
-- FSRS-5 scheduler
-- ---------------------------------------------------------------------------
create or replace function public.review_card(
  p_card_id     uuid,
  p_rating      text,
  p_duration_ms integer     default null,
  p_log_id      uuid        default null,
  p_source      text        default 'review',
  p_now         timestamptz default now()
) returns public.cards
language plpgsql
security invoker
set search_path = public
as $$
declare
  -- Intraday learning steps — unchanged from 0009/0018.
  v_learn_steps   interval[] := array['1 minute', '10 minutes']::interval[];
  v_relearn_steps interval[] := array['10 minutes']::interval[];

  -- FSRS-5 default weights (w[1]..w[19], 1-indexed for readability).
  -- Source: open-source ts-fsrs reference implementation.
  v_w double precision[] := array[
    0.4072, 1.1829, 3.1262, 15.4722, -- w[1-4]  initial stability per rating
    7.2102, 0.5316,                   -- w[5-6]  initial difficulty formula
    1.0651, 0.0589,                   -- w[7-8]  difficulty mean-reversion
    1.9395, 0.1100, 1.0145,           -- w[9-11] recall stability formula
    1.9395, 0.1100, 1.0145, 0.2232,   -- w[12-16] lapse stability formula + hard penalty
    2.9898,                           -- w[17]   easy bonus
    0.5100, 2.9898, 0.5100            -- w[18-19] short-term (unused here)
  ];

  -- FSRS constants.
  v_decay  constant double precision := -0.5;
  -- FACTOR = 0.9^(1/DECAY) - 1 = 0.9^(-2) - 1 = 100/81 - 1 = 19/81
  v_factor constant double precision := 19.0 / 81.0;
  -- Interval factor: I = S * v_ifactor gives 90%-retention interval.
  -- Derived: solve R(I,S) = 0.9 → I = S*(0.9^DECAY-1)/FACTOR = S*0.2306
  v_ifactor constant double precision := 0.2306;
  -- Hard ceiling regardless of stability. Uncapped FSRS will legitimately push
  -- a well-known card out multiple years; a language-vocab app wants a floor
  -- of contact even with words you know cold. Mirrors Anki users' common
  -- practice of setting a maximum interval rather than running uncapped.
  v_max_interval constant integer := 365;

  v_card    public.cards;
  v_word    public.words;
  v_tz      text;
  v_cutoff  integer;
  v_log_id  uuid := coalesce(p_log_id, gen_random_uuid());
  v_before  jsonb;

  v_state   text;
  v_step    smallint;
  v_ef      numeric(4,2);   -- kept for words mirror and backward compat
  v_iv      integer;
  v_reps    integer;
  v_lapses  integer;
  v_due     timestamptz;
  v_S       double precision;  -- stability
  v_D       double precision;  -- difficulty
  v_R       double precision;  -- retrievability at time of review
  v_elapsed double precision;  -- days since last review
  v_g       integer;           -- rating as integer: Again=1 Hard=2 Good=3 Easy=4
  v_D0_g    double precision;  -- D_0(G) for current rating, used in difficulty update
begin
  if p_rating not in ('again', 'hard', 'good', 'easy') then
    raise exception 'invalid rating: %', p_rating;
  end if;
  if p_source not in ('review', 'quiz', 'battle', 'drill') then
    raise exception 'invalid source: %', p_source;
  end if;

  -- Idempotency: offline retry with same log id must not re-apply.
  if p_log_id is not null
     and exists (select 1 from public.review_log where id = p_log_id) then
    select * into v_card from public.cards where id = p_card_id;
    return v_card;
  end if;

  select * into v_card from public.cards where id = p_card_id for update;
  if not found then
    raise exception 'card not found or not yours: %', p_card_id;
  end if;
  select * into v_word from public.words where id = v_card.word_id;

  v_before := to_jsonb(v_card);

  -- Non-scheduling sources: log only, never touch the card's schedule.
  -- 'quiz' is deliberately NOT in this list — Monster Hunt reschedules (0018).
  if p_source not in ('review', 'quiz') then
    insert into public.review_log (
      id, user_id, word_id, deck_id, card_id, rating,
      state_before, ease_before, interval_before, card_before,
      interval_days, duration_ms, source, reviewed_at
    ) values (
      v_log_id, v_card.user_id, v_word.id, v_word.deck_id, v_card.id, p_rating,
      v_card.state, v_card.ease_factor, v_card.interval_days, v_before,
      v_card.interval_days, p_duration_ms, p_source, p_now
    ) on conflict (id) do nothing;
    return v_card;
  end if;

  select prefs.tz, prefs.cutoff into v_tz, v_cutoff
  from public.srs_prefs(v_card.user_id) prefs;

  v_state  := v_card.state;
  v_step   := v_card.learning_step;
  v_ef     := v_card.ease_factor;
  v_iv     := v_card.interval_days;
  v_reps   := v_card.repetitions;
  v_lapses := v_card.lapses;
  v_S      := v_card.stability;
  v_D      := v_card.difficulty;

  v_g := case p_rating
           when 'again' then 1 when 'hard' then 2
           when 'good'  then 3 else 4 end;

  -- -------------------------------------------------------------------------
  -- New / learning: intraday steps (unchanged from 0018). On graduation,
  -- set initial S and D from FSRS first-review formulas.
  -- -------------------------------------------------------------------------
  if v_state in ('new', 'learning') then
    if p_rating = 'again' then
      v_state := 'learning';
      v_step  := 0;
      v_due   := p_now + v_learn_steps[1];

    elsif p_rating = 'hard' then
      v_state := 'learning';
      v_due   := p_now + v_learn_steps[least(v_step + 1, array_length(v_learn_steps, 1))];

    elsif p_rating = 'good' then
      v_step := v_step + 1;
      if v_step >= array_length(v_learn_steps, 1) then
        -- Graduated via Good.
        v_state := 'review';
        v_step  := 0;
        v_reps  := 1;
        v_S     := v_w[3];   -- S_0(Good) = w[3] = 3.1262
        v_D     := greatest(1.0, least(10.0, v_w[5] - exp(v_w[6] * 2.0) + 1.0));
        v_iv    := least(v_max_interval, greatest(1, round(v_S * v_ifactor)::integer));
        v_due   := public.srs_day_start(p_now, v_tz, v_cutoff)
                   + make_interval(days => v_iv);
      else
        v_state := 'learning';
        v_due   := p_now + v_learn_steps[v_step + 1];
      end if;

    else -- easy: skip remaining steps, graduate immediately
      v_state := 'review';
      v_step  := 0;
      v_reps  := 1;
      v_S     := v_w[4];   -- S_0(Easy) = w[4] = 15.4722
      v_D     := greatest(1.0, least(10.0, v_w[5] - exp(v_w[6] * 3.0) + 1.0));  -- D_0(Easy)
      v_iv    := least(v_max_interval, greatest(1, round(v_S * v_ifactor)::integer));
      v_due   := public.srs_day_start(p_now, v_tz, v_cutoff)
                 + make_interval(days => v_iv);
    end if;

  -- -------------------------------------------------------------------------
  -- Relearning: graduated from a lapse. On pass, use the stability stored at
  -- lapse time (S was updated by the forget formula when the lapse happened).
  -- -------------------------------------------------------------------------
  elsif v_state = 'relearning' then
    if p_rating = 'again' then
      v_step := 0;
      v_due  := p_now + v_relearn_steps[1];
    else
      v_state := 'review';
      v_step  := 0;
      -- S was set when the lapse was recorded; derive interval from it.
      -- If S is somehow null, fall back to max(1, interval_days).
      v_iv   := least(v_max_interval, greatest(1, round(coalesce(v_S, v_iv::double precision) * v_ifactor)::integer));
      v_due  := public.srs_day_start(p_now, v_tz, v_cutoff)
                + make_interval(days => v_iv);
    end if;

  -- -------------------------------------------------------------------------
  -- Review: FSRS-5 recall and lapse formulas.
  -- -------------------------------------------------------------------------
  else
    -- Retrievability at time of review.
    v_elapsed := extract(epoch from (p_now - coalesce(v_card.last_reviewed_at, p_now))) / 86400.0;

    -- Guard: if S is null (card migrated without backfill), derive it.
    if v_S is null then
      v_S := greatest(0.1, v_iv::double precision / v_ifactor);
      v_D := 5.0;
    end if;

    v_R := power(1.0 + v_factor * v_elapsed / v_S, 1.0 / v_decay);
    v_R := greatest(0.0001, least(1.0, v_R));

    -- Update difficulty.
    -- Step 1: shift by current rating.  v_w[7]=1.0651 is the per-rating step.
    -- Step 2: weakly revert toward D_0(G).  v_w[8]=0.0589 is the reversion weight.
    -- D_0(G) = clamp(v_w[5] - exp(v_w[6]*(G-1)) + 1, 1, 10)
    v_D0_g := greatest(1.0, least(10.0,
                v_w[5] - exp(v_w[6] * (v_g - 1)::double precision) + 1.0
              ));
    v_D := greatest(1.0, least(10.0,
             v_w[8] * v_D0_g
             + (1.0 - v_w[8]) * (v_D - v_w[7] * (v_g - 3)::double precision)
           ));

    if p_rating = 'again' then
      -- Lapse: stability via the forget formula.
      -- S'_f = w[12] * D^(-w[13]) * ((S+1)^(w[14])-1) * exp(w[15]*(1-R))
      v_lapses := v_lapses + 1;
      v_reps   := 0;
      v_S      := v_w[12]
                  * power(v_D, -v_w[13])
                  * (power(v_S + 1.0, v_w[14]) - 1.0)
                  * exp(v_w[15] * (1.0 - v_R));
      v_S      := greatest(0.1, v_S);
      v_state  := 'relearning';
      v_step   := 0;
      v_iv     := least(v_max_interval, greatest(1, round(v_S * v_ifactor)::integer));
      v_due    := p_now + v_relearn_steps[1];

    else
      -- Recall: stability via the recall formula.
      -- S'_r = S*(exp(w[9])*(11-D)*S^(-w[10])*(exp(w[11]*(1-R))-1)*hp*eb + 1)
      v_reps := v_reps + 1;
      v_S    := v_S * (
                  exp(v_w[9])
                  * (11.0 - v_D)
                  * power(v_S, -v_w[10])
                  * (exp(v_w[11] * (1.0 - v_R)) - 1.0)
                  -- v_w[17]=0.51 penalises Hard; v_w[16]=2.9898 boosts Easy.
                  * case when p_rating = 'hard' then v_w[17] else 1.0 end
                  * case when p_rating = 'easy' then v_w[16] else 1.0 end
                  + 1.0
                );
      v_S    := greatest(0.1, v_S);
      v_iv   := least(v_max_interval, greatest(1, round(v_S * v_ifactor)::integer));

      -- ±5% fuzz on intervals ≥ 3 days (prevents same-day imports clumping).
      if v_iv >= 3 then
        v_iv := greatest(2, round(v_iv * (1.0 + (random() - 0.5) * 0.1))::integer);
        v_iv := least(v_max_interval, v_iv);
      end if;

      v_due := public.srs_day_start(p_now, v_tz, v_cutoff)
               + make_interval(days => v_iv);
    end if;
  end if;

  -- Derive ease_factor from difficulty for the words mirror and any SM-2
  -- tooling that reads it. ef = 2.5 at D=5, shifts ±0.1 per difficulty point.
  v_ef := greatest(1.3, least(3.5, round((2.5 + (5.0 - coalesce(v_D, 5.0)) * 0.1)::numeric, 2)));

  update public.cards set
    state            = v_state,
    learning_step    = v_step,
    ease_factor      = v_ef,
    interval_days    = v_iv,
    repetitions      = v_reps,
    lapses           = v_lapses,
    due_at           = v_due,
    last_reviewed_at = p_now,
    stability        = v_S,
    difficulty       = v_D
  where id = v_card.id
  returning * into v_card;

  insert into public.review_log (
    id, user_id, word_id, deck_id, card_id, rating,
    state_before, ease_before, interval_before, card_before,
    interval_days, duration_ms, source, reviewed_at
  ) values (
    v_log_id, v_card.user_id, v_word.id, v_word.deck_id, v_card.id, p_rating,
    v_before ->> 'state', (v_before ->> 'ease_factor')::numeric,
    (v_before ->> 'interval_days')::integer, v_before,
    v_iv, p_duration_ms, p_source, p_now
  ) on conflict (id) do nothing;

  -- Words-table mirror for the still-deployed extension and web build.
  if v_card.template = 'recognition' then
    update public.words set
      ease_factor      = v_ef,
      interval_days    = v_iv,
      repetitions      = v_reps,
      due_at           = v_due,
      last_reviewed_at = p_now
    where id = v_card.word_id;
  end if;

  return v_card;
end;
$$;

-- ---------------------------------------------------------------------------
-- Undo: restated to also restore stability and difficulty (0009 original
-- listed columns explicitly and would leave them at post-review values).
-- ---------------------------------------------------------------------------
create or replace function public.undo_review(p_log_id uuid)
returns public.cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_log  public.review_log;
  v_card public.cards;
begin
  select * into v_log
  from public.review_log
  where id = p_log_id and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'review not found or not yours: %', p_log_id;
  end if;

  if v_log.undone or v_log.card_before is null then
    select * into v_card from public.cards where id = v_log.card_id;
    return v_card;
  end if;

  update public.review_log set undone = true where id = p_log_id;

  -- jsonb_populate_record fills all columns present in the snapshot, including
  -- the new stability and difficulty fields added by this migration.
  update public.cards c set
    state            = b.state,
    learning_step    = b.learning_step,
    ease_factor      = b.ease_factor,
    interval_days    = b.interval_days,
    repetitions      = b.repetitions,
    lapses           = b.lapses,
    due_at           = b.due_at,
    last_reviewed_at = b.last_reviewed_at,
    stability        = b.stability,
    difficulty       = b.difficulty
  from jsonb_populate_record(null::public.cards, v_log.card_before) b
  where c.id = v_log.card_id
  returning c.* into v_card;

  if v_card.template = 'recognition' then
    update public.words set
      ease_factor      = v_card.ease_factor,
      interval_days    = v_card.interval_days,
      repetitions      = v_card.repetitions,
      due_at           = v_card.due_at,
      last_reviewed_at = v_card.last_reviewed_at
    where id = v_card.word_id;
  end if;

  return v_card;
end;
$$;

revoke execute on function public.undo_review(uuid) from public;
grant execute on function public.undo_review(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- review_queue: add stability and difficulty to the return row so clients
-- can show accurate FSRS previews without a second fetch.
-- Also fixes the source filter (was 'review' only, should be 'review','quiz').
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
  audio_path    text
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
      w.deck_id, w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path
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
    q.term, q.reading, q.meaning, q.meaning_mn, q.audio_path
  from (select * from reviews union all select * from news) q
  order by (q.state = 'new'), q.due_at
  limit p_limit;
end;
$$;
