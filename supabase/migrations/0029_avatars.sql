-- 0029 — profile pictures you can change.
--
-- Until now profiles.image was only ever the Google photo copied in at
-- sign-up. Settings can now upload your own:
--   * a public `avatars` bucket (friends' browsers load the picture directly);
--   * each user may write only under "<their uid>/…";
--   * the client resizes to 256px WebP before upload; the bucket also caps
--     size and type, so a hand-made request can't store anything big or odd.
--
-- And a guard on profiles.image itself: friends' browsers fetch whatever URL
-- is there, so a free-form value would let anyone point it at a tracker and
-- watch who looks at them. It may only be a Google profile photo or a file in
-- this bucket. `not valid`: existing rows aren't re-checked, new writes are.
--
-- Safe to re-run.

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- Size/type limits live on newer storage.buckets columns; set them where they
-- exist (they do on Supabase).
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'storage' and table_name = 'buckets' and column_name = 'file_size_limit') then
    execute $q$update storage.buckets
               set file_size_limit = 1048576,
                   allowed_mime_types = array['image/webp', 'image/jpeg', 'image/png']
             where id = 'avatars'$q$;
  end if;
end $$;

-- Listing/deleting your own old picture goes through the storage API, which
-- needs a select policy even on a public bucket.
drop policy if exists "avatars_select_own" on storage.objects;
create policy "avatars_select_own" on storage.objects
  for select using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );
-- Viewing needs no policy: the bucket is public, served by URL.

alter table public.profiles drop constraint if exists profiles_image_source;
alter table public.profiles
  add constraint profiles_image_source check (
    image is null
    or image ~ '^https://lh[0-9]+\.googleusercontent\.com/'
    or image ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/avatars/'
  ) not valid;
