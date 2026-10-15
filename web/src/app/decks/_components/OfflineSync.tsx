"use client";

import { useEffect } from "react";
import { supabase } from "../_lib/db";
import { cacheQueue } from "../_lib/offline";
import { kv } from "../_lib/offlineStore";
import { flushOfflineAnswers } from "../_lib/usePracticeSession";

/** The pages a session can be started from, saved so they open offline. */
const WARM = ["/decks/stats", "/decks/review", "/decks/practice", "/decks/review/battle"];
const WARM_KEY = "hanko.sw.warmedAt";
const WARM_EVERY_MS = 12 * 3600 * 1000;

/**
 * Background upkeep for offline review (_lib/offline.ts), mounted once in the
 * /decks layout; renders nothing:
 *   - registers the service worker (public/sw.js) — production only, so
 *     `next dev` never caches anything;
 *   - sends answers given offline, on load and whenever the browser comes
 *     back online;
 *   - refreshes the saved copy of the whole due queue, so a session started
 *     with no connection has cards to show;
 *   - asks the service worker to save the session pages, twice a day.
 * Every step fails silently: none of it is needed while online.
 */
export default function OfflineSync() {
  useEffect(() => {
    if (process.env.NODE_ENV === "production" && "serviceWorker" in navigator) {
      navigator.serviceWorker
        .register("/sw.js", { scope: "/", updateViaCache: "none" })
        .then(() => navigator.serviceWorker.ready)
        .then((reg) => {
          let last = 0;
          try {
            last = Number(localStorage.getItem(WARM_KEY)) || 0;
          } catch {}
          if (Date.now() - last < WARM_EVERY_MS || !navigator.onLine) return;
          reg.active?.postMessage({ type: "warm", urls: WARM });
          try {
            localStorage.setItem(WARM_KEY, String(Date.now()));
          } catch {}
        })
        .catch(() => {});
    }

    let busy = false;
    async function sync() {
      if (busy || !navigator.onLine) return;
      busy = true;
      try {
        await flushOfflineAnswers();
        const { data, error } = await supabase.rpc("review_queue", { p_deck_id: null, p_limit: 60 });
        if (!error) await cacheQueue(kv, null, "due", data ?? []);
      } catch {
      } finally {
        busy = false;
      }
    }
    // After the page's own requests, not competing with them.
    const t = setTimeout(sync, 2000);
    window.addEventListener("online", sync);
    return () => {
      clearTimeout(t);
      window.removeEventListener("online", sync);
    };
  }, []);
  return null;
}
