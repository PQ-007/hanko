-- Vocab Decks schema: profiles (1:1 with auth.users), decks, words.
-- All tables are protected by Row Level Security so each user can only ever
-- see/modify their own rows. This is what makes it safe for the browser
-- extension to talk to the Supabase REST API directly with the anon key.

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  email      text,
  name       text,
  image      text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- Auto-create a profile row whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, image)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- shared updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- decks
-- ---------------------------------------------------------------------------
create table if not exists public.decks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted    boolean not null default false   -- tombstone for sync
);

create index if not exists decks_user_id_idx on public.decks (user_id);
create index if not exists decks_updated_at_idx on public.decks (updated_at);

alter table public.decks enable row level security;

create policy "decks_select_own" on public.decks
  for select using (auth.uid() = user_id);
create policy "decks_insert_own" on public.decks
  for insert with check (auth.uid() = user_id);
create policy "decks_update_own" on public.decks
  for update using (auth.uid() = user_id);
create policy "decks_delete_own" on public.decks
  for delete using (auth.uid() = user_id);

create trigger decks_touch_updated_at
  before update on public.decks
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- words
-- ---------------------------------------------------------------------------
create table if not exists public.words (
  id         uuid primary key default gen_random_uuid(),
  deck_id    uuid not null references public.decks on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  term       text not null,
  reading    text,
  meaning    text,
  audio_path text,                              -- Storage path, nullable
  date_added timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted    boolean not null default false
);

create index if not exists words_deck_id_idx on public.words (deck_id);
create index if not exists words_user_id_idx on public.words (user_id);
create index if not exists words_updated_at_idx on public.words (updated_at);

alter table public.words enable row level security;

create policy "words_select_own" on public.words
  for select using (auth.uid() = user_id);
create policy "words_insert_own" on public.words
  for insert with check (auth.uid() = user_id);
create policy "words_update_own" on public.words
  for update using (auth.uid() = user_id);
create policy "words_delete_own" on public.words
  for delete using (auth.uid() = user_id);

create trigger words_touch_updated_at
  before update on public.words
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Storage bucket for per-word audio (private; RLS-scoped by user folder)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('word-audio', 'word-audio', false)
on conflict (id) do nothing;

-- Files are stored under "<user_id>/<word_id>.mp3"; users may only touch
-- objects whose first path segment is their own uid.
create policy "word_audio_select_own" on storage.objects
  for select using (
    bucket_id = 'word-audio' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "word_audio_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'word-audio' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "word_audio_update_own" on storage.objects
  for update using (
    bucket_id = 'word-audio' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "word_audio_delete_own" on storage.objects
  for delete using (
    bucket_id = 'word-audio' and (storage.foldername(name))[1] = auth.uid()::text
  );
