"use client";

import type { KV } from "./offline";

// The browser side of offline.ts: one IndexedDB object store used as a
// key-value map. IndexedDB rather than localStorage because a queue of cards
// with example sentences can outgrow localStorage's few megabytes, and it
// doesn't block the page while it writes.
//
// Every call fails soft: a private window or blocked storage means "no
// offline copy", never a broken review screen.

const DB = "hanko-offline";
const STORE = "kv";

let opening: Promise<IDBDatabase> | null = null;

function open(): Promise<IDBDatabase> {
  opening ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  opening.catch(() => {
    opening = null;
  });
  return opening;
}

function run<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest): Promise<T> {
  return open().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const req = fn(db.transaction(STORE, mode).objectStore(STORE));
        req.onsuccess = () => resolve(req.result as T);
        req.onerror = () => reject(req.error);
      })
  );
}

export const kv: KV = {
  get: <T>(key: string) => run<T | undefined>("readonly", (s) => s.get(key)).catch(() => undefined),
  set: (key, value) => run<void>("readwrite", (s) => s.put(value, key)),
  del: (key) => run<void>("readwrite", (s) => s.delete(key)).catch(() => {}),
};

/**
 * Forgets everything this browser kept for offline use — the cached queues,
 * the word list, unsent answers and the service worker's saved pages — so the
 * next person on a shared computer finds nothing. Called on sign-out.
 */
export async function clearOfflineData(): Promise<void> {
  try {
    opening = null;
    await new Promise<void>((resolve) => {
      const req = indexedDB.deleteDatabase(DB);
      req.onsuccess = req.onerror = req.onblocked = () => resolve();
    });
  } catch {}
  try {
    for (const key of await caches.keys()) {
      if (key.startsWith("hanko-")) await caches.delete(key);
    }
  } catch {}
}
