-- Spaced-repetition (SM-2) scheduling state for words. One word = one card.

alter table public.words add column if not exists ease_factor numeric(4,2) not null default 2.5;
alter table public.words add column if not exists interval_days integer not null default 0;
alter table public.words add column if not exists repetitions integer not null default 0;
alter table public.words add column if not exists due_at timestamptz not null default now();
alter table public.words add column if not exists last_reviewed_at timestamptz;

create index if not exists words_due_idx on public.words (user_id, due_at) where deleted = false;
