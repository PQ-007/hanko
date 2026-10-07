-- Mobile parity: nested folders, plus the two numbers the stats page shows
-- that nothing could answer before — retention/accuracy and a forecast of
-- upcoming reviews.
--
-- Safe to re-run: guarded alters, drop-before-create for every function whose
-- row type is declared here, drop-if-exists before the trigger.

-- ---------------------------------------------------------------------------
-- Nested folders
-- ---------------------------------------------------------------------------
-- `on delete set null` only covers a hard delete. Folders are tombstoned
-- (deleted = true), which leaves children pointing at a dead parent — both
-- clients treat a parent they can't see as "root", the same way the web
-- already treats a deck whose folder was deleted as unfiled. No cascade of
-- writes needed on delete.
alter table public.folders
  add column if not exists parent_id uuid references public.folders(id) on delete set null;

create index if not exists folders_parent_idx on public.folders (parent_id);

-- Rejects a parent that isn't the caller's own folder and any chain that
-- loops back to the folder being written. Runs as the invoker, so the lookup
-- is RLS-scoped: someone else's folder id simply isn't found.
create or replace function public.folders_check_parent()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_cur   uuid := new.parent_id;
  v_depth integer := 0;
begin
  if new.parent_id is null then
    return new;
  end if;
  if new.parent_id = new.id then
    raise exception 'a folder cannot be its own parent';
  end if;
  if not exists (
    select 1 from public.folders where id = new.parent_id and user_id = new.user_id
  ) then
    raise exception 'parent folder not found';
  end if;

  while v_cur is not null loop
    if v_cur = new.id then
      raise exception 'folder cycle';
    end if;
    v_depth := v_depth + 1;
    if v_depth > 32 then
      raise exception 'folders nested too deep';
    end if;
    select parent_id into v_cur from public.folders where id = v_cur;
  end loop;

  return new;
end;
$$;

drop trigger if exists folders_check_parent on public.folders;
create trigger folders_check_parent
  before insert or update of parent_id on public.folders
  for each row execute function public.folders_check_parent();

-- ---------------------------------------------------------------------------
-- review_stats: accuracy over every scheduling answer, and retention over
-- answers to cards that were already in review — the FSRS sense of the word,
-- where "hard" is still a successful recall and only "again" is a lapse.
-- Same filters as due_summary()/review_activity(): review + quiz only (battle
-- and drill are guesses under a timer), undone answers excluded.
-- Percentages are null, not 0, when there's nothing in the window.
-- ---------------------------------------------------------------------------
drop function if exists public.review_stats(integer);

create function public.review_stats(p_days integer default 30)
returns table (
  total          integer,
  correct        integer,
  accuracy_pct   numeric,
  review_total   integer,
  review_correct integer,
  retention_pct  numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    count(*)::integer,
    count(*) filter (where l.rating <> 'again')::integer,
    case when count(*) = 0 then null
         else round(100.0 * count(*) filter (where l.rating <> 'again') / count(*), 1) end,
    count(*) filter (where l.state_before = 'review')::integer,
    count(*) filter (where l.state_before = 'review' and l.rating <> 'again')::integer,
    case when count(*) filter (where l.state_before = 'review') = 0 then null
         else round(
           100.0 * count(*) filter (where l.state_before = 'review' and l.rating <> 'again')
                 / count(*) filter (where l.state_before = 'review'),
           1) end
  from public.review_log l
  where l.user_id = auth.uid()
    and l.source in ('review', 'quiz')
    and l.undone = false
    and l.reviewed_at >= now() - make_interval(days => p_days);
$$;

-- ---------------------------------------------------------------------------
-- review_forecast: review cards falling due on each of the next p_days SRS
-- days. Overdue cards are counted on today. New cards are left out — they're
-- gated by the daily new-card cap, not by a due date, so counting them would
-- forecast a wall that never arrives.
-- ---------------------------------------------------------------------------
drop function if exists public.review_forecast(integer);

create function public.review_forecast(p_days integer default 30)
returns table (
  day date,
  due integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_tz          text;
  v_cutoff      integer;
  v_today_start timestamptz;
begin
  select prefs.tz, prefs.cutoff
    into v_tz, v_cutoff
  from public.srs_prefs(v_user) prefs;

  v_today_start := public.srs_day_start(now(), v_tz, v_cutoff);

  -- No aliases in the select list: RETURNS TABLE columns are plpgsql
  -- variables, so naming a result column `day` would be ambiguous (same note
  -- as review_activity in 0013).
  return query
  select
    ((public.srs_day_start(greatest(c.due_at, v_today_start), v_tz, v_cutoff))
      at time zone coalesce(v_tz, 'UTC'))::date,
    count(*)::integer
  from public.cards c
  join public.words w on w.id = c.word_id
  where c.user_id = v_user
    and c.suspended = false
    and w.deleted = false
    and c.state <> 'new'
    and c.due_at < v_today_start + make_interval(days => p_days)
  group by 1
  order by 1;
end;
$$;
