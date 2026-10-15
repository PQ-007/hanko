import type { QueueCard } from "./types.ts";

// Offline review for the web, the same shape as mobile's
// core/offline_review.dart — and, like it, deliberately NOT a sync engine:
//
//   - a cache of the last queue the server handed us, replaced wholesale,
//     never merged, never used to decide what is due;
//   - a durable outbox of answers, replayed in order through review_card().
//
// Replay is safe only because review_card() is idempotent on the client-made
// log id (Phase 0.5): an answer whose reply was lost can be sent again without
// counting twice.
//
// One deliberate difference from mobile: only a *network* failure is queued.
// A server that answers with an error still behaves exactly as before this
// file existed (the card goes back, the error shows), so nothing about the
// online site changes.
//
// Pure, with the storage injected, so offline.test.ts can pin it in node.

export interface PendingAnswer {
  logId: string;
  cardId: string;
  rating: string;
  durationMs: number | null;
  source: string;
  answeredAt: number;
}

/** A tiny key-value store: IndexedDB in the browser (offlineStore.ts), a Map in tests. */
export interface KV {
  get<T>(key: string): Promise<T | undefined>;
  set(key: string, value: unknown): Promise<void>;
  del(key: string): Promise<void>;
}

const OUTBOX = "outbox";
const WORDS = "words";

export const queueKey = (deckId: string | null, mode: string) => `queue:${mode}:${deckId ?? "all"}`;

/**
 * Whether a Supabase error is "the request never got an answer" rather than
 * "the server said no". supabase-js reports a failed fetch as an error with
 * no code and the browser's own message ("Failed to fetch", Safari's "Load
 * failed", Firefox's "NetworkError…"); a real server error always has a code.
 */
export function isNetworkError(
  error: { message?: string; code?: string } | null | undefined,
  online: boolean = typeof navigator === "undefined" ? true : navigator.onLine
): boolean {
  if (!error) return false;
  if (error.code) return false;
  if (!online) return true;
  return /failed to fetch|load failed|networkerror|network request failed|fetch failed/i.test(error.message ?? "");
}

// One tab's outbox writes go through this chain, so two quick answers can't
// read-modify-write over each other.
let chain: Promise<unknown> = Promise.resolve();
function serial<T>(fn: () => Promise<T>): Promise<T> {
  const next = chain.then(fn, fn);
  chain = next.catch(() => {});
  return next;
}

export function pending(kv: KV): Promise<PendingAnswer[]> {
  return kv.get<PendingAnswer[]>(OUTBOX).then((list) => list ?? []);
}

export function enqueue(kv: KV, answer: PendingAnswer): Promise<void> {
  return serial(async () => {
    const list = await pending(kv);
    // The log id is the idempotency key: the same answer twice is one answer.
    await kv.set(OUTBOX, [...list.filter((a) => a.logId !== answer.logId), answer]);
  });
}

/** Removes a queued answer; true if it was queued (so it never reached the server). */
export function dropPending(kv: KV, logId: string): Promise<boolean> {
  return serial(async () => {
    const list = await pending(kv);
    const rest = list.filter((a) => a.logId !== logId);
    if (rest.length === list.length) return false;
    await kv.set(OUTBOX, rest);
    return true;
  });
}

export async function cacheQueue(kv: KV, deckId: string | null, mode: string, cards: QueueCard[]) {
  await kv.set(queueKey(deckId, mode), cards);
}

/**
 * The last queue fetched for this deck and mode — or, for a deck never opened
 * online, its cards from the whole-library queue — minus anything answered
 * and still waiting in the outbox (it's done until the server has scheduled
 * it). Null when there is no copy at all.
 */
export async function cachedQueue(kv: KV, deckId: string | null, mode: string): Promise<QueueCard[] | null> {
  let cards = await kv.get<QueueCard[]>(queueKey(deckId, mode));
  // A deck never opened online: its share of the whole due queue, which the
  // app keeps fresh in the background (OfflineSync.tsx).
  if (!cards && deckId) cards = (await kv.get<QueueCard[]>(queueKey(null, mode)))?.filter((c) => c.deck_id === deckId);
  if (!cards) return null;
  const answered = new Set((await pending(kv)).map((a) => a.cardId));
  return cards.filter((c) => !answered.has(c.card_id));
}

export function cacheWords<T>(kv: KV, words: T[]) {
  return kv.set(WORDS, words);
}

export function cachedWords<T>(kv: KV): Promise<T[] | undefined> {
  return kv.get<T[]>(WORDS);
}

export type Send = (a: PendingAnswer) => PromiseLike<{ error: { message?: string; code?: string } | null }>;

/**
 * Replays queued answers oldest first. Stops at the first network failure, so
 * the order holds and a still-offline device doesn't spin through the
 * backlog. An answer the server refuses outright (its card deleted, say) is
 * dropped rather than left to block every answer behind it forever.
 */
export function flush(kv: KV, send: Send): Promise<{ sent: number; dropped: number; left: number }> {
  return serial(async () => {
    const list = [...(await pending(kv))].sort((a, b) => a.answeredAt - b.answeredAt);
    let sent = 0;
    let dropped = 0;
    let i = 0;
    for (; i < list.length; i++) {
      let error: { message?: string; code?: string } | null;
      try {
        ({ error } = await send(list[i]));
      } catch (e) {
        error = { message: e instanceof Error ? e.message : String(e) };
      }
      if (error && isNetworkError(error)) break;
      if (error) dropped++;
      else sent++;
    }
    const left = list.slice(i);
    await kv.set(OUTBOX, left);
    return { sent, dropped, left: left.length };
  });
}
