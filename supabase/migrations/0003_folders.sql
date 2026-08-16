-- Folders to organize decks. A deck optionally belongs to one folder.

create table if not exists public.folders (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted    boolean not null default false
);

create index if not exists folders_user_id_idx on public.folders (user_id);

alter table public.folders enable row level security;

create policy "folders_select_own" on public.folders
  for select using (auth.uid() = user_id);
create policy "folders_insert_own" on public.folders
  for insert with check (auth.uid() = user_id);
create policy "folders_update_own" on public.folders
  for update using (auth.uid() = user_id);
create policy "folders_delete_own" on public.folders
  for delete using (auth.uid() = user_id);

create trigger folders_touch_updated_at
  before update on public.folders
  for each row execute function public.touch_updated_at();

-- Link decks to a folder (nullable = "no folder"). Deleting a folder leaves its
-- decks intact, just unfiled.
alter table public.decks
  add column if not exists folder_id uuid references public.folders(id) on delete set null;
