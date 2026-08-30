-- Make Monster Hunt answers identifiable without making them fake.
--
-- Scored Monster Hunt writes real schedules, and should: it is genuine recall
-- practice that happens to be under a timer. But it was writing them as
-- source='review' — byte-identical to a classic self-rated session — so there
-- was no way to ask whether a mode with a 25% guess floor (four options, one
-- right) schedules as reliably as one without. review_log already carries
-- ease_before and interval_before from Phase 0.4; the missing piece was a
-- label separating the two populations.
--
-- 'quiz' therefore behaves EXACTLY like 'review' everywhere — scheduling,
-- streaks, the heatmap, the daily caps — and differs only in being nameable in
-- a query. 'battle' (the unbuilt PvP mode) and 'drill' (speed round) keep their
-- existing meaning: logged, never scheduled.
--
-- Three functions are restated below rather than patched, because Postgres has
-- no way to edit a function body in place. Same pattern 0012 used to add a
-- parameter to due_summary(). THE COPIES HERE SUPERSEDE 0009 AND 0012/0013 —
-- a later change to the scheduler must be made here, not there.
--
-- The trap this migration exists to avoid: review_activity() and due_summary()
-- both filter on source = 'review'. Widening the source without widening those
-- two would, on the day it shipped, silently stop the heatmap, the streak and
-- the daily caps from counting Monster Hunt sessions — the mode most people
-- use — with nothing erroring anywhere.
--
-- Safe to re-run: every statement is guarded or a create-or-replace.

-- 1. Allow the value ---------------------------------------------------------
alter table public.review_log
  drop constraint if exists review_log_source_check;
alter table public.review_log
  add constraint review_log_source_check
  check (source in ('review', 'quiz', 'battle', 'drill'));

-- 2. Schedule on it ----------------------------------------------------------
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
  if p_source not in ('review', 'quiz', 'battle', 'drill') then
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
  --
  -- 'quiz' is deliberately NOT one of them. Monster Hunt is real recall
  -- practice that happens to be under a timer; it has always rescheduled, and
  -- the only thing this migration changes is that its rows are now labelled so
  -- the two populations can be compared. Moving it to the log-only branch would
  -- silently stop the app's main practice mode from scheduling anything.
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

-- 3. Count it in the daily caps ----------------------------------------------
-- Unchanged from 0012 apart from the source filter.
drop function if exists public.due_summary(uuid);
drop function if exists public.due_summary(uuid, timestamptz);

create function public.due_summary(
  p_deck_id uuid        default null,
  p_at      timestamptz default now()
) returns table (
  due_now          integer,  -- what a session started at p_at would serve
  review_due       integer,  -- review/learning cards due, ignoring caps
  new_due          integer,  -- new cards available, ignoring caps
  review_remaining integer,  -- that day's unspent review allowance
  new_remaining    integer   -- that day's unspent new-card allowance
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

  -- The SRS day containing p_at. For a reminder scheduled after the next
  -- cutoff this is a *later* day than today, so the caps come back unspent —
  -- which is the correct forecast: tomorrow's allowance is untouched.
  v_day_start := public.srs_day_start(p_at, v_tz, v_cutoff);

  select
    count(*) filter (where state_before = 'new'),
    count(*) filter (where state_before is not null and state_before <> 'new')
  into v_new_done, v_rev_done
  from public.review_log
  where user_id = v_user
    and source in ('review', 'quiz')
    and undone = false
    and reviewed_at >= v_day_start
    and reviewed_at <= p_at;

  select
    count(*) filter (where c.state <> 'new'),
    count(*) filter (where c.state = 'new')
  into review_due, new_due
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = v_user
    and c.suspended = false
    and w.deleted = false
    and (p_deck_id is null or w.deck_id = p_deck_id)
    and c.due_at <= p_at;

  review_remaining := greatest(v_rev_cap - v_rev_done, 0);
  new_remaining    := greatest(v_new_cap - v_new_done, 0);
  due_now := least(review_due, review_remaining) + least(new_due, new_remaining);

  return next;
end;
$$;

-- 4. Count it as study -------------------------------------------------------
-- Unchanged from 0013 apart from the source filter.
drop function if exists public.review_activity(integer);

create function public.review_activity(p_days integer default 400)
returns table (
  day     date,
  reviews integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_tz     text;
  v_cutoff integer;
begin
  select prefs.tz, prefs.cutoff
    into v_tz, v_cutoff
  from public.srs_prefs(v_user) prefs;

  -- No aliases in the select list on purpose: the RETURNS TABLE columns are
  -- plpgsql variables, so naming a result column `day` here would be ambiguous.
  return query
  select
    ((public.srs_day_start(l.reviewed_at, v_tz, v_cutoff))
      at time zone coalesce(v_tz, 'UTC'))::date,
    count(*)::integer
  from public.review_log l
  where l.user_id = v_user
    and l.source in ('review', 'quiz')   -- battle/drill answers never count as study
    and l.undone = false          -- nor do answers the user took back
    and l.reviewed_at >= now() - make_interval(days => p_days)
  group by 1
  order by 1;
end;
$$;
