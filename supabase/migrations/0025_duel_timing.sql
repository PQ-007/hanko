-- 0025 — duel round timing, matched to the clients again.
--
-- duel.ts (web) and duel_rules.dart (mobile) were changed to a 10 s first
-- round tightening 500 ms a round to a 6 s floor, "raised on request (5 s read
-- as too short in play)". This function — which begin_round() uses to issue
-- each PvP round's server deadline — still had the original 5 s / 250 ms /
-- 3 s curve. In a real match the server closed rounds at 5 s while both
-- players' clocks still showed time left, and clamped every answer slower
-- than that. Found by probing the live database while porting the duel to
-- mobile.
--
-- Re-runnable: create or replace, same signature and return type.

create or replace function public.duel_round_duration_ms(p_round_no integer)
returns integer
language sql
immutable
as $$
  select greatest(6000, 10000 - (greatest(1, p_round_no) - 1) * 500);
$$;
