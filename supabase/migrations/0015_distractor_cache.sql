-- A growing cache of real Jisho lookups, used to generate plausible wrong
-- answers for the Monster Hunt quiz mode. NOT a bulk-imported dictionary —
-- it starts empty and fills up from real API results as /api/distractors is
-- called, same as the existing /api/lookup already calls Jisho live. See
-- CLAUDE.md's plan notes: an earlier draft of this feature proposed
-- importing a JMdict dataset wholesale, which was unnecessary complexity for
-- infrastructure (Jisho) this repo already has working.

create table if not exists public.distractor_cache (
  id             uuid primary key default gen_random_uuid(),
  term           text not null,
  reading        text,
  meaning        text not null,
  part_of_speech text,
  term_length    int generated always as (char_length(term)) stored,
  created_at     timestamptz not null default now(),
  unique (term, part_of_speech)
);

create index if not exists distractor_cache_pos_len_idx
  on public.distractor_cache (part_of_speech, term_length);

alter table public.distractor_cache enable row level security;

-- Fully public reads (`using (true)`), not `auth.role() = 'authenticated'`:
-- this is non-sensitive shared reference data (real dictionary words pulled
-- from Jisho, nothing user-specific) — the same "no auth needed" stance
-- /api/lookup already takes. The reading route also has no session/cookie
-- context to present as an authenticated role in the first place, so
-- requiring authentication here would have silently made every read fail
-- (falls back to the anon role, which an authenticated-only policy rejects)
-- and the cache would never appear warm.
drop policy if exists "distractor_cache_select_any" on public.distractor_cache;
create policy "distractor_cache_select_any" on public.distractor_cache
  for select using (true);

-- No insert/update/delete policy for the publishable-key role on purpose:
-- the cache is written only by the /api/distractors route using the
-- service-role key (bypasses RLS by design, same pattern as
-- handle_new_user()'s security definer trigger in 0001_init.sql). Letting
-- any authenticated client's own token write here would let a hostile
-- signed-in user poison shared reference data shown to every other user's
-- quiz — the route is the only trusted writer.
