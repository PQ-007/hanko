-- Reverts 0015_distractor_cache.sql. Real playtesting found the Jisho-backed
-- distractor generation (live API calls + a growing Postgres cache) too slow
-- per question — Monster Hunt's wrong-answer options now come from the
-- player's own word library instead: one query when the battle screen
-- mounts, then picked in memory with zero network calls per question. See
-- CLAUDE.md's plan notes and web/src/app/decks/review/battle/_lib/quiz.ts.
--
-- No data loss of consequence: this table only ever held cached lookups of
-- common dictionary words, freely re-fetchable from Jisho if this pattern is
-- ever revisited — nothing user-owned lived here.

drop policy if exists "distractor_cache_select_any" on public.distractor_cache;
drop table if exists public.distractor_cache;
