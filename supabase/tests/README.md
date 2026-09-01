# Migration checks

Not a test framework — there is no `supabase` CLI in this repo and migrations
are applied by hand. These are SQL scripts you can paste into the Supabase SQL
editor, or run against a throwaway Postgres.

## Running them against a throwaway Postgres

```bash
podman run -d --name hanko-pg -e POSTGRES_PASSWORD=pg docker.io/library/postgres:16
podman exec -i hanko-pg psql -U postgres -c 'create database hanko;'
podman exec -i hanko-pg psql -U postgres -d hanko < supabase/tests/bootstrap.sql
for f in supabase/migrations/*.sql; do
  podman exec -i hanko-pg psql -U postgres -d hanko -v ON_ERROR_STOP=1 -q < "$f" || break
done
podman exec -i hanko-pg psql -U postgres -d hanko < supabase/tests/duel_damage_fixture.sql
```

`bootstrap.sql` stands in for the parts of Supabase the migrations reference
(`auth.users`, `auth.uid()`, `storage.buckets`, the `authenticated`/`anon`
roles, the `supabase_realtime` publication). It is not a Supabase emulator and
does not need to be — the migrations only touch those few surfaces.

## `duel_damage_fixture.sql`

Checks `duel_damage()` against `web/src/app/decks/review/duel/_lib/duel.fixture.json`,
the same 484 cases `duel.test.ts` pins the TypeScript against. The two
implementations exist for a reason (PVP.md 3.3) and this is what stops them
drifting. Expected output is `disagree = 0`.

Regenerate the fixture only when the damage rules are *meant* to change —
regenerating it to make a failure go away launders a real behaviour change
into a green test.
