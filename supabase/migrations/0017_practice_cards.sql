-- Free practice: any of the user's cards, regardless of whether they're due.
--
-- review_queue() deliberately answers "what does the scheduler want you to do
-- today" — day cutoff, daily caps, due_at. That's correct for real review,
-- but it means a user who has already cleared their queue is told "nothing to
-- do" when they simply want to practice. This RPC answers a different
-- question: "give me cards to play with."
--
-- Answers from this queue MUST be logged with source='drill', never 'review'
-- (see review_card() in 0009: any non-'review' source logs the answer and
-- returns the card completely untouched). Reviewing a card early doesn't
-- improve retention, and letting off-schedule practice reschedule real cards
-- would corrupt the scheduling this whole system exists to protect. It also
-- keeps drills out of streaks/stats, which filter on source='review'
-- (review_activity(), 0013).
--
-- Shape matches review_queue()/mature_cards() exactly, so the same client
-- code renders either one.

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
  audio_path    text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    c.id, c.word_id, w.deck_id, c.template, c.state, c.learning_step, c.due_at,
    c.interval_days, c.repetitions, c.ease_factor,
    w.term, w.reading, w.meaning, w.meaning_mn, w.audio_path
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = auth.uid()
    and c.suspended = false
    and w.deleted = false
    and (p_deck_id is null or w.deck_id = p_deck_id)
  -- Random rather than due-order: this is practice, so there's no schedule to
  -- respect, and a fixed order would drill the same words first every time.
  order by random()
  limit p_limit;
$$;
