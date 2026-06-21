# Vocab Decks — companion to 10ten Japanese Reader

A small browser extension that lets you save words you look up (with 10ten,
or just by selecting text) into your own decks, then export a deck as a file
Anki can import directly. 10ten itself doesn't support saving words, so this
runs alongside it rather than modifying it.

## How to use it day to day

1. Browse normally, look words up with 10ten as usual.
2. When you want to keep a word: select the text, then either
   - right-click it and choose **"Save '...' to vocab deck"**, or
   - press **Alt+Shift+S** (works on whatever's currently selected).
3. A small panel appears with the reading and meaning already filled in
   (via Jisho's dictionary API) — edit them if you want, pick or create a
   deck, and click **Save word**.
4. Click the extension icon any time to see your decks, review/delete
   words, or export a deck.

## Installing in Chrome

1. Go to `chrome://extensions`.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked**.
4. Select the `chrome/` folder from this project.
5. Pin the extension icon if you want quick access to the deck dashboard.

## Installing in Firefox

1. Go to `about:debugging#/runtime/this-firefox`.
2. Click **Load Temporary Add-on…**.
3. Select the `manifest.json` file inside the `firefox/` folder.
4. Note: temporary add-ons are removed when Firefox restarts. For a
   permanent install you'd package and self-sign it, or submit it to
   addons.mozilla.org (even as an unlisted/private add-on) — ask me if
   you want help with that step later.

## Exporting to Anki

Click the extension icon → pick a deck → **Export deck for Anki (.txt)**.
This downloads a tab-separated file with one word per line:

```
term (reading)    meaning    deck-name-as-tag
```

In Anki:

1. **File → Import…**
2. Select the downloaded `.txt` file.
3. Set **Type** to "Notetype: Basic" (or whatever note type you prefer).
4. Set **Fields separated by** to **Tab**.
5. Map column 1 → **Front**, column 2 → **Back**. Column 3 (the tag) can
   be mapped to **Tags** if you want every imported card auto-tagged with
   the deck name, or just leave it unmapped/ignored.
6. Pick the destination Anki deck and click **Import**.

## Notes & limitations

- Dictionary auto-fill uses Jisho's public API. It's a well-known, widely
  used endpoint but unofficial, so if it ever goes down the reading/meaning
  fields just stay blank and you can type them in manually — saving still
  works.
- By default everything is stored locally in the browser via `storage.local`.
  Sign in (see below) to sync your decks to your account and back them up in
  the cloud. Signed out, the extension stays fully local as before.
- The keyboard shortcut can be changed at `chrome://extensions/shortcuts`
  (Chrome) or in the add-on's settings (Firefox) if Alt+Shift+S conflicts
  with something else.

## Project structure

```
src/                 shared source files (sync module, config example)
chrome/              ready-to-load Chrome build (Manifest V3, service worker)
firefox/             ready-to-load Firefox build (Manifest V3, scripts background)
icons/               shared placeholder icons
web/                 companion website (Next.js + Supabase)
supabase/            database schema migration
```

## Companion website & cross-device sync

The `web/` app lets you sign in with Google, manage your decks in a fuller
dashboard, sync them across every browser/device, generate **real `.apkg`**
files (with embedded audio), and pull in **pronunciation audio** per word.
Saved words from the extension sync to the same account.

See **[SETUP.md](SETUP.md)** for the full walkthrough (Supabase project, Google
sign-in, running the site, and connecting the extension).
