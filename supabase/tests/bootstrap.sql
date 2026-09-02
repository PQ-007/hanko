-- Minimal stand-in for the parts of Supabase the migrations touch.
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb
);
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
-- Realtime publication, so the 0020 block exercises its real path.
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
create schema if not exists storage;
create table if not exists storage.buckets (
  id text primary key, name text, public boolean default false
);
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text, name text, owner uuid, metadata jsonb
);
create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$ select string_to_array(name, '/'); $$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
end $$;
-- Supabase grants the authenticated role usage on public by default; mirror it
-- so RLS is what the tests are actually exercising.
grant usage on schema public to authenticated, anon;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant select on auth.users to authenticated;

-- Supabase's default privileges: `authenticated` gets ALL on public tables, and
-- RLS is what actually restricts them. Mirrored here so the migration tests
-- exercise the real arrangement — in particular that a table with no UPDATE
-- policy is unwritable even by a role holding the UPDATE privilege, which is
-- why the duel's lifecycle functions have to be SECURITY DEFINER.
alter default privileges in schema public grant all on tables to authenticated, anon;
alter default privileges in schema public grant all on sequences to authenticated, anon;
alter default privileges in schema public grant execute on functions to authenticated, anon;
