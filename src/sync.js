// Shared sync module (canonical copy in src/; copied verbatim into chrome/ and
// firefox/ because the extension has no build step and each manifest loads its
// own local files).
//
// Talks to Supabase directly over its REST + Auth HTTP APIs using plain fetch —
// no @supabase/supabase-js bundle required. Row Level Security on the server
// keeps every request scoped to the signed-in user, so the anon key is safe to
// ship. Requires config.js (loaded first) to define window.VOCAB_CONFIG with
// SUPABASE_URL, SUPABASE_ANON_KEY and SITE_URL.
//
// Local store shape (storage.local):
//   decks: [{ id, name, createdAt, updatedAt, deleted }]
//   words: [{ id, deckId, term, reading, meaning, dateAdded, updatedAt, deleted, ... }]
//   session: { access_token, refresh_token }
//   lastPushedAt: number (ms, *local* clock)  — cursor over our own edits
//   lastPulledAt: number (ms, *server* clock) — cursor over remote updated_at
//   lastSyncedAt: number (ms)                 — legacy single cursor, still
//                                               written for older builds
//
// Deletions are tombstones (deleted: true) so they propagate; the UI filters
// them out. Conflict resolution is last-write-wins by updatedAt.

const VocabSync = (() => {
  const ctx = typeof browser !== "undefined" ? browser : chrome;
  const cfg = globalThis.VOCAB_CONFIG || {};
  // Accept either the new publishable key (sb_publishable_...) or a legacy anon
  // key — both work as the Supabase apikey for client requests.
  const ANON = cfg.SUPABASE_PUBLISHABLE_KEY || cfg.SUPABASE_ANON_KEY || "";
  const REST = () => `${cfg.SUPABASE_URL}/rest/v1`;
  const AUTH = () => `${cfg.SUPABASE_URL}/auth/v1`;

  // Slack applied to the pull cursor. Covers the Date header's one-second
  // granularity plus rows committed while a sync is in flight; the pull filter
  // is `gte`, so a little overlap costs one redundant row and last-write-wins
  // makes re-applying it a no-op.
  const SKEW_MARGIN_MS = 5000;

  function configured() {
    return Boolean(cfg.SUPABASE_URL && ANON && cfg.SITE_URL);
  }

  // ---- session storage ----
  async function getSession() {
    const { session } = await ctx.storage.local.get("session");
    return session || null;
  }
  async function setSession(session) {
    await ctx.storage.local.set({ session });
  }
  async function signOut() {
    await ctx.storage.local.remove([
      "session",
      "lastSyncedAt",
      "lastPushedAt",
      "lastPulledAt",
    ]);
  }

  function decodeJwt(token) {
    try {
      const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      return JSON.parse(atob(payload));
    } catch {
      return {};
    }
  }

  // Returns a valid access token, refreshing if it's about to expire, or null
  // if the user isn't signed in / the refresh failed.
  async function validAccessToken() {
    const session = await getSession();
    if (!session?.access_token) return null;
    const { exp } = decodeJwt(session.access_token);
    if (exp && Date.now() / 1000 < exp - 60) return session.access_token;

    const res = await fetch(`${AUTH()}/token?grant_type=refresh_token`, {
      method: "POST",
      headers: { apikey: ANON, "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: session.refresh_token }),
    });
    if (!res.ok) {
      await signOut();
      return null;
    }
    const refreshed = await res.json();
    await setSession({
      access_token: refreshed.access_token,
      refresh_token: refreshed.refresh_token,
    });
    return refreshed.access_token;
  }

  async function rest(path, { method = "GET", token, body, prefer } = {}) {
    const headers = {
      apikey: ANON,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    };
    if (prefer) headers.Prefer = prefer;
    const res = await fetch(`${REST()}/${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) throw new Error(`Supabase REST ${res.status}: ${await res.text()}`);
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  // Postgres stamps updated_at from the *server* clock, so the pull cursor has
  // to be expressed in server time. The Date response header is the cheapest
  // way to read that clock — one-second granularity, which SKEW_MARGIN_MS
  // covers. Returns null if it can't be read, and the caller then leaves the
  // pull cursor where it is rather than guessing.
  async function serverNow(token) {
    try {
      const res = await fetch(`${REST()}/decks?select=id&limit=1`, {
        headers: { apikey: ANON, Authorization: `Bearer ${token}` },
      });
      const header = res.headers.get("date");
      const ms = header ? Date.parse(header) : NaN;
      return Number.isNaN(ms) ? null : ms;
    } catch {
      return null;
    }
  }

  // ---- store access ----
  async function getStore() {
    const data = await ctx.storage.local.get([
      "decks",
      "words",
      "lastPushedAt",
      "lastPulledAt",
      "lastSyncedAt",
    ]);
    return {
      decks: data.decks || [],
      words: data.words || [],
      // Upgrading from the single lastSyncedAt: keep it as the push cursor (it
      // was always local time and still means the right thing), but reset the
      // pull cursor to 0 so the next sync re-pulls everything once. That one
      // full pull repairs any rows the old skew-prone cursor jumped over.
      lastPushedAt: data.lastPushedAt ?? data.lastSyncedAt ?? 0,
      lastPulledAt: data.lastPulledAt ?? 0,
    };
  }

  // ---- field mapping (local <-> remote rows) ----
  const ms = (iso) => (iso ? Date.parse(iso) : 0);
  const iso = (n) => new Date(n || Date.now()).toISOString();

  function deckToRow(d, userId) {
    return {
      id: d.id,
      user_id: userId,
      name: d.name,
      folder_id: d.folderId || null,
      created_at: iso(d.createdAt),
      updated_at: iso(d.updatedAt || d.createdAt),
      deleted: !!d.deleted,
    };
  }
  function rowToDeck(r) {
    return {
      id: r.id,
      name: r.name,
      folderId: r.folder_id || null,
      createdAt: ms(r.created_at),
      updatedAt: ms(r.updated_at),
      deleted: !!r.deleted,
    };
  }
  function wordToRow(w, userId) {
    return {
      id: w.id,
      deck_id: w.deckId,
      user_id: userId,
      term: w.term,
      reading: w.reading || null,
      meaning: w.meaning || null,
      meaning_mn: w.meaningMn || null,
      date_added: iso(w.dateAdded),
      updated_at: iso(w.updatedAt || w.dateAdded),
      deleted: !!w.deleted,
    };
  }
  function rowToWord(r) {
    return {
      id: r.id,
      deckId: r.deck_id,
      term: r.term,
      reading: r.reading || "",
      meaning: r.meaning || "",
      meaningMn: r.meaning_mn || "",
      dateAdded: ms(r.date_added),
      updatedAt: ms(r.updated_at),
      deleted: !!r.deleted,
      audioPath: r.audio_path || null,
    };
  }

  // Ensure every local item has updatedAt so the change cursor works for data
  // created before sync existed.
  function backfill(store) {
    let changed = false;
    for (const d of store.decks) {
      if (d.updatedAt == null) {
        d.updatedAt = d.createdAt || Date.now();
        changed = true;
      }
    }
    for (const w of store.words) {
      if (w.updatedAt == null) {
        w.updatedAt = w.dateAdded || Date.now();
        changed = true;
      }
    }
    return changed;
  }

  function mergeById(localList, remoteRows, toLocal) {
    const byId = new Map(localList.map((x) => [x.id, x]));
    for (const row of remoteRows) {
      const incoming = toLocal(row);
      const existing = byId.get(incoming.id);
      // Last-write-wins: take remote only if it's newer (or new to us).
      if (!existing || incoming.updatedAt >= (existing.updatedAt || 0)) {
        byId.set(incoming.id, incoming);
      }
    }
    return [...byId.values()];
  }

  // Push local changes since the last sync, then pull remote changes. Returns
  // { signedIn, pushed, pulled } or { signedIn: false }.
  async function fullSync() {
    if (!configured()) return { signedIn: false, reason: "unconfigured" };
    const token = await validAccessToken();
    if (!token) return { signedIn: false };
    const userId = decodeJwt(token).sub;

    // Read the clock BEFORE snapshotting the store. An edit that lands between
    // the two is absent from this snapshot, so it must still be >= the cursor
    // we save — otherwise it belongs to no sync at all and is lost silently.
    const localStart = Date.now();
    const store = await getStore();
    backfill(store);
    const serverStart = await serverNow(token);

    // PUSH — our own edits are stamped with the local clock, so the cursor that
    // selects them stays in local time.
    const since = store.lastPushedAt || 0;
    // `>=`, not `>`: an edit stamped at exactly the cursor would otherwise fall
    // through the gap between two syncs and never be pushed. Re-pushing a row
    // occasionally is free — the write is an idempotent upsert under
    // last-write-wins — whereas dropping one is silent data loss.
    const deckRows = store.decks
      .filter((d) => (d.updatedAt || 0) >= since)
      .map((d) => deckToRow(d, userId));
    const wordRows = store.words
      .filter((w) => (w.updatedAt || 0) >= since)
      .map((w) => wordToRow(w, userId));
    if (deckRows.length) {
      await rest("decks?on_conflict=id", {
        method: "POST",
        token,
        body: deckRows,
        prefer: "resolution=merge-duplicates",
      });
    }
    if (wordRows.length) {
      await rest("words?on_conflict=id", {
        method: "POST",
        token,
        body: wordRows,
        prefer: "resolution=merge-duplicates",
      });
    }

    // PULL (everything changed at/after our cursor, including our own writes —
    // harmless under LWW). First sync (cursor 0) pulls everything.
    //
    // This cursor is deliberately NOT the local clock. It used to be, and a
    // device running even slightly ahead of Postgres would write a cursor in
    // the future — every row committed inside that window was then filtered out
    // of every subsequent pull and never seen again. Silent, permanent, and
    // invisible until someone noticed a missing word.
    const sinceIso = new Date(store.lastPulledAt || 0).toISOString();
    const remoteDecks = await rest(
      `decks?select=*&updated_at=gte.${encodeURIComponent(sinceIso)}`,
      { token }
    );
    const remoteWords = await rest(
      `words?select=*&updated_at=gte.${encodeURIComponent(sinceIso)}`,
      { token }
    );

    const merged = await getStore(); // re-read in case of concurrent writes
    backfill(merged);
    merged.decks = mergeById(merged.decks, remoteDecks || [], rowToDeck);
    merged.words = mergeById(merged.words, remoteWords || [], rowToWord);

    await ctx.storage.local.set({
      decks: merged.decks,
      words: merged.words,
      lastPushedAt: localStart,
      // Only advance the pull cursor when the server clock was actually
      // readable. If it wasn't, staying put means the next sync re-pulls a
      // window we've already seen — wasteful but lossless, which is the right
      // way round for a cursor to fail.
      lastPulledAt:
        serverStart != null
          ? Math.max(0, serverStart - SKEW_MARGIN_MS)
          : store.lastPulledAt,
      // Legacy key, still written so an older extension build downgraded onto
      // this store keeps working.
      lastSyncedAt: localStart,
    });

    return {
      signedIn: true,
      pushed: deckRows.length + wordRows.length,
      pulled: (remoteDecks?.length || 0) + (remoteWords?.length || 0),
    };
  }

  // Sign in by opening the website's /extension/connect page in a normal tab.
  // The user completes Google sign-in there; the page hands the session to our
  // content-script bridge (see content.js), which forwards it to the background
  // to store (STORE_SESSION). This avoids identity.launchWebAuthFlow, which is
  // unreliable in Firefox.
  function signIn() {
    if (!configured()) return { ok: false, error: "Extension not configured" };
    const url = `${cfg.SITE_URL.replace(/\/$/, "")}/extension/connect`;
    ctx.tabs.create({ url });
    return { ok: true };
  }

  // Store a session received from the connect-page bridge, then sync.
  async function storeSession(access_token, refresh_token) {
    if (!access_token || !refresh_token) return { ok: false };
    await setSession({ access_token, refresh_token });
    await fullSync();
    return { ok: true };
  }

  async function status() {
    const session = await getSession();
    if (!session?.access_token) return { signedIn: false, configured: configured() };
    const { email, sub } = decodeJwt(session.access_token);
    return { signedIn: true, configured: configured(), email, userId: sub };
  }

  return { fullSync, signIn, signOut, status, configured, storeSession };
})();

globalThis.VocabSync = VocabSync;
