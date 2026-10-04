-- Bounds on the daily caps now that the dashboard lets a user set new_per_day
-- directly (GoalModal, writes straight to profiles — same RLS-permitted
-- direct-update pattern EnsureTimezone.tsx already uses for timezone, no RPC
-- gate). profiles_update_own has no WITH CHECK, so without a constraint here
-- a client could write a negative or absurd value straight through RLS.
-- Mirrors the pattern profiles_streak_freezes_check set in 0014.
--
-- Safe to re-run: drop-if-exists before each add.
alter table public.profiles
  drop constraint if exists profiles_new_per_day_check;
alter table public.profiles
  add constraint profiles_new_per_day_check
  check (new_per_day between 0 and 999);

alter table public.profiles
  drop constraint if exists profiles_reviews_per_day_check;
alter table public.profiles
  add constraint profiles_reviews_per_day_check
  check (reviews_per_day between 0 and 9999);
