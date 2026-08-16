-- One transactional review path, server-side.
--
-- Today web/src/app/decks/practice/_components/PracticeSession.tsx updates
-- `words` and inserts into `review_log` as two independent calls, and the log
-- insert swallows every error (`.then(undefined, () => {})`) — a failed insert
-- silently loses history. Worse, mobile would need its own copy of the SM-2
-- logic, and two hand-written schedulers drift.
--
-- review_card() is the single source of truth: it applies the schedule, writes
-- the log, and mirrors state back into `words` for the still-deployed clients,
-- all in one transaction. SECURITY INVOKER, so RLS decides which cards a caller
-- may touch.
--
-- The SM-2 arithmetic below mirrors web/src/lib/srs.ts exactly (same ease
-- formula, same per-rating multipliers, same graduated floor) so migrating the
-- web practice screen onto this RPC doesn't move anybody's cards. What is new:
-- intraday learning steps, interval fuzz, and day-aligned due dates.

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
  -- Intraday steps. A new card currently jumps straight to a 1-day interval;
  -- short steps are what make new material stick.
  v_learn_steps   interval[] := array['1 minute', '10 minutes']::interval[];
  v_relearn_steps interval[] := array['10 minutes']::interval[];

  v_card    public.cards;
  v_word    public.words;
  v_tz      text;
  v_cutoff  integer;
  v_log_id  uuid := coalesce(p_log_id, gen_random_uuid());
  v_before  jsonb;

  v_state   text;
  v_step    smallint;
  v_ef      numeric(4,2);
  v_iv      integer;
  v_reps    integer;
  v_lapses  integer;
  v_due     timestamptz;

  v_q       integer;
  v_factor  numeric;
  v_grown   integer;
  v_floor   integer;
begin
  if p_rating not in ('again', 'hard', 'good', 'easy') then
    raise exception 'invalid rating: %', p_rating;
  end if;
  if p_source not in ('review', 'battle', 'drill') then
    raise exception 'invalid source: %', p_source;
  end if;

  -- Idempotency. An offline client retries with the same device-generated log
  -- id; the answer must not be applied a second time.
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

  -- Gamified answers are logged but never reschedule. Enforced here rather than
  -- in each client so no future caller can quietly corrupt the SRS signal.
  if p_source <> 'review' then
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

  -- ---------------------------------------------------------------------
  -- New / learning: work through the intraday steps.
  -- ---------------------------------------------------------------------
  if v_state in ('new', 'learning') then
    if p_rating = 'again' then
      v_state := 'learning';
      v_step  := 0;
      v_due   := p_now + v_learn_steps[1];

    elsif p_rating = 'hard' then
      -- Hard repeats the step the card is sitting on. learning_step is the
      -- 0-based index of that step; the array is 1-based, hence the +1. Without
      -- the offset every Hard fell back to the first step, making it identical
      -- to Again.
      v_state := 'learning';
      v_due   := p_now + v_learn_steps[least(v_step + 1, array_length(v_learn_steps, 1))];

    elsif p_rating = 'good' then
      v_step := v_step + 1;
      if v_step >= array_length(v_learn_steps, 1) then
        v_state := 'review';                      -- graduated
        v_step  := 0;
        v_reps  := 1;
        v_iv    := 1;
        v_due   := public.srs_day_start(p_now, v_tz, v_cutoff)
                   + make_interval(days => v_iv);
      else
        v_state := 'learning';
        v_due   := p_now + v_learn_steps[v_step + 1];
      end if;

    else -- easy: skip the remaining steps
      v_state := 'review';
      v_step  := 0;
      v_reps  := 1;
      v_iv    := 4;
      v_due   := public.srs_day_start(p_now, v_tz, v_cutoff)
                 + make_interval(days => v_iv);
    end if;

  -- ---------------------------------------------------------------------
  -- Relearning: a lapsed review card working its way back.
  -- ---------------------------------------------------------------------
  elsif v_state = 'relearning' then
    if p_rating = 'again' then
      v_step := 0;
      v_due  := p_now + v_relearn_steps[1];
    else
      v_state := 'review';
      v_step  := 0;
      v_iv    := greatest(1, v_iv);
      v_due   := public.srs_day_start(p_now, v_tz, v_cutoff)
                 + make_interval(days => v_iv);
    end if;

  -- ---------------------------------------------------------------------
  -- Review: SM-2 proper, identical to web/src/lib/srs.ts.
  -- ---------------------------------------------------------------------
  else
    v_q := case p_rating
             when 'again' then 0 when 'hard' then 3
             when 'good'  then 4 else 5 end;

    -- Ease is updated before this answer's own interval is computed; applying
    -- it only from the next review is what used to make Hard/Easy inert.
    v_ef := greatest(1.3, v_ef + (0.1 - (5 - v_q) * (0.08 + (5 - v_q) * 0.02)));

    if p_rating = 'again' then
      -- Lapse. Note this drops ease by 0.8 (classic SM-2, inherited from
      -- srs.ts); Anki uses 0.20. Left as-is deliberately so the migration
      -- doesn't silently reschedule everyone — tune it as its own change.
      v_lapses := v_lapses + 1;
      v_reps   := 0;
      v_iv     := 1;
      v_state  := 'relearning';
      v_step   := 0;
      v_due    := p_now + v_relearn_steps[1];
    else
      v_reps := v_reps + 1;
      if v_reps = 1 then
        v_iv := case when p_rating = 'easy' then 4 else 1 end;
      elsif v_reps = 2 then
        v_iv := case p_rating when 'hard' then 3 when 'easy' then 8 else 6 end;
      else
        v_factor := case p_rating
                      when 'hard' then 1.2
                      when 'easy' then v_ef * 1.3
                      else v_ef end;
        -- Easy rounds up so it can't collide with Good on short intervals.
        v_grown := case when p_rating = 'easy'
                        then ceil(v_iv * v_factor)
                        else round(v_iv * v_factor) end;
        -- A passing answer never leaves the card on the same interval, and the
        -- floor is graduated by rating so a better answer always buys strictly
        -- more time even at low ease.
        v_floor := v_iv + case p_rating when 'hard' then 1 when 'easy' then 3 else 2 end;
        v_iv    := greatest(v_floor, v_grown);
      end if;

      -- ±5% fuzz once the interval is long enough for it to matter. Without it,
      -- everything imported on the same day comes back on the same day forever.
      if v_iv >= 3 then
        v_iv := greatest(2, round(v_iv * (1 + (random() - 0.5) * 0.1))::integer);
      end if;

      v_due := public.srs_day_start(p_now, v_tz, v_cutoff)
               + make_interval(days => v_iv);
    end if;
  end if;

  update public.cards set
    state            = v_state,
    learning_step    = v_step,
    ease_factor      = v_ef,
    interval_days    = v_iv,
    repetitions      = v_reps,
    lapses           = v_lapses,
    due_at           = v_due,
    last_reviewed_at = p_now
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

  -- Compatibility shim: the deployed extension and web build still read the SRS
  -- columns on `words`. Remove together with those columns (see 0006).
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
-- Undo the last answer.
--
-- The practice screen already has an Undo button, which today works by holding
-- the log row back in memory until the next answer. That trick dies once the
-- write is atomic and server-side — and it never worked across devices. Instead
-- the log row is marked `undone` and the card is restored from the snapshot.
--
-- SECURITY DEFINER because review_log has no update policy (history must not be
-- rewritable from a client); ownership is checked explicitly below.
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

  update public.cards c set
    state            = b.state,
    learning_step    = b.learning_step,
    ease_factor      = b.ease_factor,
    interval_days    = b.interval_days,
    repetitions      = b.repetitions,
    lapses           = b.lapses,
    due_at           = b.due_at,
    last_reviewed_at = b.last_reviewed_at
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
