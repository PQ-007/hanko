-- Add a Mongolian translation field to words (English meaning -> Mongolian).
alter table public.words add column if not exists meaning_mn text;
