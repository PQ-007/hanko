-- Web Push reminders: the web app's "N cards are due" — mobile's daily local
-- notification (core/reminders.dart), for browsers and the installed web app
-- (iPhone included, once added to the home screen).
--
-- A browser can't schedule a notification for itself, so the server sends it:
--   1. a browser that turns reminders on stores its push subscription here,
--      with the hour it wants them (one row per browser, like mobile's
--      per-device setting);
--   2. once an hour, /api/push/remind (web) asks push_targets() who is due a
--      reminder right now, and sends each one through the browser's push
--      service;
--   3. a subscription the push service says is gone is removed with
--      push_drop().
--
-- The count is due_summary()'s due_now for that user — the same number the
-- dashboard shows and a session would serve, so a reminder can't promise 47
-- cards and hand out 20. Nothing is sent when nothing is due.
--
-- What triggers step 2 is not in this file, because it needs the site's URL
-- and a secret: see the pg_cron snippet at the bottom.
--
-- Safe to re-run.

create table if not exists public.push_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  endpoint      text not null unique,
  p256dh        text not null,
  auth          text not null,
  -- Local hour (profiles.timezone) to remind at; 9 is mobile's default.
  remind_hour   smallint not null default 9 check (remind_hour between 0 and 23),
  -- The user's local date of the last reminder: one a day at most.
  last_sent_on  date,
  created_at    timestamptz not null default now()
);

create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists "push_select_own" on public.push_subscriptions;
create policy "push_select_own" on public.push_subscriptions
  for select using (user_id = auth.uid());
drop policy if exists "push_insert_own" on public.push_subscriptions;
create policy "push_insert_own" on public.push_subscriptions
  for insert with check (user_id = auth.uid());
drop policy if exists "push_update_own" on public.push_subscriptions;
create policy "push_update_own" on public.push_subscriptions
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "push_delete_own" on public.push_subscriptions;
create policy "push_delete_own" on public.push_subscriptions
  for delete using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- push_targets(): who gets a reminder this hour, claimed in the same call.
-- ---------------------------------------------------------------------------
-- A subscription is due when it's its hour in its user's timezone and it
-- hasn't had today's reminder yet. Claiming (setting last_sent_on) happens
-- here, before anything is sent, so two overlapping runs can't both send it;
-- a send that then fails just means no reminder that day.
--
-- due_now comes from due_summary() itself, run as each user: auth.uid()
-- reads request.jwt.claim.sub, which this function sets per user for the
-- rest of its own transaction. That keeps one definition of "what's due"
-- instead of a copy here that could drift from the dashboard's.
--
-- Service role only: it reads every user's subscriptions.

drop function if exists public.push_targets(timestamptz);
create function public.push_targets(p_now timestamptz default now())
returns table (id uuid, endpoint text, p256dh text, auth text, due_now integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_due integer;
begin
  for r in
    with claimed as (
      update public.push_subscriptions s
      set last_sent_on = (p_now at time zone coalesce(p.timezone, 'UTC'))::date
      from public.profiles p
      where p.id = s.user_id
        and extract(hour from p_now at time zone coalesce(p.timezone, 'UTC')) = s.remind_hour
        and (s.last_sent_on is null
             or s.last_sent_on < (p_now at time zone coalesce(p.timezone, 'UTC'))::date)
      returning s.id, s.user_id, s.endpoint, s.p256dh, s.auth
    )
    select * from claimed
  loop
    perform set_config('request.jwt.claim.sub', r.user_id::text, true);
    select d.due_now into v_due from public.due_summary(null, p_now) d;
    if coalesce(v_due, 0) > 0 then
      id := r.id;
      endpoint := r.endpoint;
      p256dh := r.p256dh;
      auth := r.auth;
      due_now := v_due;
      return next;
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- A subscription the push service answered 404/410 for: the browser dropped
-- it (permission revoked, site data cleared), so stop trying.
drop function if exists public.push_drop(text[]);
create function public.push_drop(p_endpoints text[])
returns integer
language sql
security definer
set search_path = public
as $$
  with gone as (
    delete from public.push_subscriptions where endpoint = any(p_endpoints) returning 1
  )
  select count(*)::integer from gone;
$$;

revoke execute on function public.push_targets(timestamptz) from public, anon, authenticated;
revoke execute on function public.push_drop(text[]) from public, anon, authenticated;
grant execute on function public.push_targets(timestamptz) to service_role;
grant execute on function public.push_drop(text[]) to service_role;

-- ---------------------------------------------------------------------------
-- The hourly trigger — run once by hand in the SQL editor, NOT part of this
-- migration (it carries the site URL and a secret, which don't belong in the
-- repo). Needs the pg_cron and pg_net extensions (Database → Extensions).
-- <SITE> is the deployed web app, <CRON_SECRET> the same value as the web
-- app's CRON_SECRET environment variable.
--
--   select cron.schedule('hanko-push-remind', '0 * * * *', $cron$
--     select net.http_post(
--       url     := '<SITE>/api/push/remind',
--       headers := jsonb_build_object('Authorization', 'Bearer <CRON_SECRET>')
--     );
--   $cron$);
--
-- To stop it: select cron.unschedule('hanko-push-remind');
-- ---------------------------------------------------------------------------
