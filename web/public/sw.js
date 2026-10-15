// Hanko's service worker: what lets the installed web app open and review
// with no connection (decks/_lib/offline.ts holds the data side), and later
// receive "cards due" pushes.
//
// Deliberately narrow, because a service worker that gets it wrong breaks
// the site for everyone who has it until they clear their browser:
//
//   - only this site's own GET requests; Supabase, Tatoeba, Google and every
//     other origin pass straight through, untouched;
//   - never /api, /auth, /login or /extension;
//   - pages are network-first: online, every page is exactly what the server
//     sends; the saved copy is only a fallback when the network fails, and
//     only /decks pages are saved;
//   - /_next/static files are content-hashed and never change, so those are
//     cache-first.
//
// Kill switch: if this ever misbehaves, replace this file with
//   self.addEventListener("install", () => self.skipWaiting());
//   self.addEventListener("activate", (e) => e.waitUntil(
//     caches.keys().then((ks) => Promise.all(ks.map((k) => caches.delete(k))))
//       .then(() => self.registration.unregister())));
// and deploy — every browser drops it on its next visit.

const VERSION = "v1";
// Registered as /sw.js?dev=1 from `next dev` (ReminderSettings.tsx): reminders
// only, no caching — dev builds reuse file names for changed code, and a
// cache-first copy would hide every edit.
const DEV = new URL(self.location.href).searchParams.has("dev");
const STATIC = `hanko-static-${VERSION}`;
const PAGES = `hanko-pages-${VERSION}`;
const ASSETS = `hanko-assets-${VERSION}`;
const KEEP = [STATIC, PAGES, ASSETS];

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key.startsWith("hanko-") && !KEEP.includes(key)) await caches.delete(key);
      }
      await self.clients.claim();
    })()
  );
});

const SKIP = ["/api/", "/auth/", "/login", "/extension", "/sw.js"];

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  const path = url.pathname;
  if (DEV || SKIP.some((p) => path.startsWith(p))) return;

  if (path.startsWith("/_next/static/")) {
    event.respondWith(cacheFirst(req, STATIC));
  } else if (req.mode === "navigate" && path.startsWith("/decks")) {
    event.respondWith(page(req));
  } else if (/\.(png|webp|jpg|jpeg|gif|svg|woff2?)$/.test(path)) {
    // Sprites, icons, fonts: as fresh as the network gives them, kept for
    // when it doesn't.
    event.respondWith(networkFirst(req, ASSETS));
  }
  // Anything else — Next's client-side navigation requests among them — goes
  // to the network as if this file didn't exist. Offline, a failed client
  // navigation makes Next load the page in full, which page() then serves.
});

async function cacheFirst(req, name) {
  const cache = await caches.open(name);
  const hit = await cache.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok) cache.put(req, res.clone());
  return res;
}

async function networkFirst(req, name) {
  const cache = await caches.open(name);
  try {
    const res = await fetch(req);
    if (res.ok && res.type === "basic") cache.put(req, res.clone());
    return res;
  } catch (e) {
    const hit = await cache.match(req);
    if (hit) return hit;
    throw e;
  }
}

/** A /decks page: the network's answer, or the last copy saved of it offline. */
async function page(req) {
  const cache = await caches.open(PAGES);
  try {
    const res = await fetch(req);
    // A redirect (signed out → /login) is never saved as the page.
    if (res.ok && res.type === "basic" && !res.redirected) cache.put(req, res.clone());
    return res;
  } catch {
    return (
      (await cache.match(req)) ||
      // ?deck=… and the like: the page reads them itself.
      (await cache.match(req, { ignoreSearch: true })) ||
      (await cache.match("/decks/stats", { ignoreSearch: true })) ||
      offlinePage()
    );
  }
}

function offlinePage() {
  return new Response(
    `<!doctype html><html lang="mn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Hanko</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:system-ui,sans-serif;background:#f7eedd;color:#3b2f24;text-align:center;padding:24px}
@media (prefers-color-scheme:dark){body{background:#17140f;color:#e9e2d5}}button{margin-top:16px;padding:10px 18px;border-radius:10px;border:1px solid currentColor;background:none;color:inherit;font:inherit}</style></head>
<body><div><p style="font-size:18px;font-weight:600">Интернэт холболт алга</p><p style="opacity:.75">Энэ хуудсыг өмнө нь нээж байгаагүй тул офлайнаар харуулах хуулбар алга.</p>
<button onclick="location.reload()">Дахин оролдох</button></div></body></html>`,
    { status: 503, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}

// "Warm" the pages a session can be started from, so they open offline even if
// this browser never visited them since installing: the app asks for this in
// the background (OfflineSync.tsx), at most twice a day.
self.addEventListener("message", (event) => {
  const data = event.data || {};
  if (data.type === "warm" && Array.isArray(data.urls)) event.waitUntil(warm(data.urls));
});

async function warm(urls) {
  const pages = await caches.open(PAGES);
  const statics = await caches.open(STATIC);
  for (const url of urls) {
    try {
      const res = await fetch(url, { credentials: "same-origin" });
      if (!res.ok || res.redirected) continue;
      const html = await res.clone().text();
      await pages.put(url, res);
      // The page's own scripts and styles, so it can actually start offline.
      const files = new Set(html.match(/\/_next\/static\/[^"'\s)]+/g) || []);
      for (const file of files) {
        if (!(await statics.match(file))) {
          const r = await fetch(file);
          if (r.ok) await statics.put(file, r);
        }
      }
    } catch {
      // Offline or the server busy: try again next time.
    }
  }
  await trim(statics, 400);
}

/** Old builds' files pile up across deploys: keep the newest `max`. */
async function trim(cache, max) {
  const keys = await cache.keys();
  for (let i = 0; i < keys.length - max; i++) await cache.delete(keys[i]);
}

// ---------------------------------------------------------------------------
// Reminders (0033_web_push.sql): the server pushes { title, body, url, tag }.
// ---------------------------------------------------------------------------
self.addEventListener("push", (event) => {
  let msg = {};
  try {
    msg = event.data ? event.data.json() : {};
  } catch {}
  event.waitUntil(
    self.registration.showNotification(msg.title || "Hanko", {
      body: msg.body || "",
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      tag: msg.tag || "hanko",
      data: { url: msg.url || "/decks/review" },
    })
  );
});

// A tap opens the app where the notification points, reusing a window that's
// already open rather than stacking a new one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || "/decks/review", self.location.origin).href;
  event.waitUntil(
    (async () => {
      const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      const open = wins.find((w) => new URL(w.url).origin === self.location.origin);
      if (open) {
        await open.focus();
        if ("navigate" in open) return open.navigate(url).catch(() => {});
        return;
      }
      return self.clients.openWindow(url);
    })()
  );
});
