# Setup — Vocab Decks website + sync

This guide wires up the companion website (`web/`), the Supabase backend, and
the browser extension so your decks sync across devices and export to real
`.apkg` files. Steps marked **(manual)** are things only you can do in a
browser dashboard.

## 1. Create a Supabase project (manual)

1. Go to <https://supabase.com> → **New project**. Pick a name and a strong DB
   password; wait for it to provision.
2. In **Project Settings → API**, copy:
   - **Project URL** (e.g. `https://abcd1234.supabase.co`)
   - **anon public** key
   These are the same public values used by both the website and the extension.

## 2. Apply the database schema

The schema (tables, Row Level Security, triggers, the audio storage bucket)
lives in [supabase/migrations/0001_init.sql](supabase/migrations/0001_init.sql).

Easiest path: open the Supabase **SQL Editor**, paste the file's contents, and
**Run**. (Or, with the [Supabase CLI](https://supabase.com/docs/guides/cli):
`supabase link` then `supabase db push`.)

## 3. Configure Google sign-in (manual)

1. In **Google Cloud Console** → *APIs & Services → Credentials* → **Create
   OAuth client ID** → *Web application*.
2. Under **Authorized redirect URIs**, add Supabase's callback:
   `https://YOUR-PROJECT.supabase.co/auth/v1/callback`
3. Copy the **Client ID** and **Client secret**.
4. In **Supabase → Authentication → Providers → Google**, paste them and enable
   the provider.
5. In **Supabase → Authentication → URL Configuration → Redirect URLs**, allow
   the website's callback/connect URLs (add both localhost and your real domain):
   - `http://localhost:3000/auth/callback`
   - `http://localhost:3000/extension/connect`
   - `https://YOUR-DOMAIN/auth/callback`
   - `https://YOUR-DOMAIN/extension/connect`

## 4. Run the website locally

```bash
cd web
cp .env.local.example .env.local   # then fill in the values from step 1
npm install
npm run dev
```

`.env.local`:

```
NEXT_PUBLIC_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=YOUR-ANON-KEY
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

Open <http://localhost:3000>, sign in with Google, and you should land on the
deck dashboard. Create a deck, add a word (reading/meaning auto-fill via Jisho),
and try **Export .apkg** — import the file in Anki to confirm.

Optional audio: the **▶** button next to a word generates pronunciation via the
default unofficial Google Translate TTS (no key needed). To use the official
Google Cloud TTS instead, set `TTS_PROVIDER=google-cloud` and
`GOOGLE_CLOUD_TTS_API_KEY=...` in `.env.local`.

## 5. Deploy the website (manual, optional)

Push the repo to GitHub and import `web/` into **Vercel**. Set the same three
`NEXT_PUBLIC_*` env vars (use your real domain for `NEXT_PUBLIC_SITE_URL`).
Re-check that your production URLs are in the Supabase redirect allowlist
(step 3.5).

## 6. Point the extension at your project

Edit **both** `chrome/config.js` and `firefox/config.js` (copies of
[src/config.example.js](src/config.example.js)) with the same public values:

```js
globalThis.VOCAB_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
  SUPABASE_ANON_KEY: "YOUR-ANON-KEY",
  SITE_URL: "http://localhost:3000", // or your deployed site
};
```

Then load the extension (see the main [README](README.md)). Click the
extension icon → **Sign in**. A Google window opens; after you approve, the
popup shows **Synced · your@email**. From then on:

- Words you save from any page upload to your account.
- Decks/words created on the website appear in the popup (sync runs on popup
  open, after each save, and every 5 minutes in the background).
- Deletions propagate as tombstones, so removing a word in one place removes it
  everywhere.

Signed out, the extension behaves exactly as before — everything stays local.

## How the pieces fit

- **Auth, database, REST API, RLS** → Supabase. The extension talks to Supabase
  directly (RLS keeps each user to their own rows), so there's no custom sync
  server.
- **Website UI + `.apkg`/audio generation** → Next.js (`web/`). Only the things
  that need server logic (building the Anki package, calling TTS) are API routes.
- **Extension** → unchanged local-first behavior, plus a small fetch-based sync
  layer ([src/sync.js](src/sync.js)) and a Google connect flow.
