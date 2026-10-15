import { test } from "node:test";
import assert from "node:assert/strict";
import {
  cachedQueue,
  cacheQueue,
  dropPending,
  enqueue,
  flush,
  isNetworkError,
  pending,
  type KV,
  type PendingAnswer,
} from "./offline.ts";
import type { QueueCard } from "./types.ts";

function memory(): KV {
  const m = new Map<string, unknown>();
  return {
    get: async <T,>(k: string) => structuredClone(m.get(k)) as T | undefined,
    set: async (k, v) => void m.set(k, structuredClone(v)),
    del: async (k) => void m.delete(k),
  };
}

const card = (id: string, deck = "d1") => ({ card_id: id, deck_id: deck, term: id }) as QueueCard;
const answer = (logId: string, cardId: string, at: number): PendingAnswer => ({
  logId,
  cardId,
  rating: "good",
  durationMs: 1000,
  source: "review",
  answeredAt: at,
});
const NET = { message: "TypeError: Failed to fetch", code: "" };

test("a network failure is told apart from a server that said no", () => {
  assert.equal(isNetworkError(NET, true), true);
  assert.equal(isNetworkError({ message: "TypeError: Load failed" }, true), true, "Safari");
  assert.equal(isNetworkError({ message: "NetworkError when attempting to fetch resource." }, true), true, "Firefox");
  assert.equal(isNetworkError({ message: "anything", code: "" }, false), true, "the browser says it's offline");
  assert.equal(isNetworkError({ message: "permission denied", code: "42501" }, true), false);
  assert.equal(isNetworkError({ message: "Failed to fetch", code: "PGRST202" }, false), false, "a code means the server answered");
  assert.equal(isNetworkError(null, false), false);
});

test("the cached queue leaves out cards answered while offline", async () => {
  const kv = memory();
  assert.equal(await cachedQueue(kv, null, "due"), null, "no copy at all");
  await cacheQueue(kv, null, "due", [card("a"), card("b"), card("c")]);
  await enqueue(kv, answer("l1", "b", 1));
  assert.deepEqual((await cachedQueue(kv, null, "due"))?.map((c) => c.card_id), ["a", "c"]);
});

test("a deck never opened online gets its share of the whole-library queue", async () => {
  const kv = memory();
  assert.equal(await cachedQueue(kv, "d2", "due"), null);
  await cacheQueue(kv, null, "due", [card("a", "d1"), card("b", "d2"), card("c", "d2")]);
  await enqueue(kv, answer("l1", "c", 1));
  assert.deepEqual((await cachedQueue(kv, "d2", "due"))?.map((c) => c.card_id), ["b"]);
  await cacheQueue(kv, "d2", "due", [card("z", "d2")]);
  assert.deepEqual((await cachedQueue(kv, "d2", "due"))?.map((c) => c.card_id), ["z"], "its own copy wins");
  assert.equal(await cachedQueue(kv, null, "free"), null, "per mode");
});

test("the outbox: one answer per log id, and undo drops only what never left", async () => {
  const kv = memory();
  await Promise.all([enqueue(kv, answer("l1", "a", 1)), enqueue(kv, answer("l2", "b", 2)), enqueue(kv, answer("l1", "a", 1))]);
  assert.deepEqual((await pending(kv)).map((a) => a.logId), ["l2", "l1"]);
  assert.equal(await dropPending(kv, "l1"), true);
  assert.equal(await dropPending(kv, "l1"), false);
  assert.deepEqual((await pending(kv)).map((a) => a.logId), ["l2"]);
});

test("replay goes oldest first and stops at the first network failure, keeping the rest in order", async () => {
  const kv = memory();
  await enqueue(kv, answer("late", "c", 3));
  await enqueue(kv, answer("early", "a", 1));
  await enqueue(kv, answer("mid", "b", 2));
  const sent: string[] = [];
  const r = await flush(kv, async (a) => {
    if (a.logId === "mid") return { error: NET };
    sent.push(a.logId);
    return { error: null };
  });
  assert.deepEqual(sent, ["early"]);
  assert.deepEqual(r, { sent: 1, dropped: 0, left: 2 });
  assert.deepEqual((await pending(kv)).map((a) => a.logId), ["mid", "late"]);
});

test("an answer the server refuses is dropped, not left to block the rest", async () => {
  const kv = memory();
  await enqueue(kv, answer("gone", "a", 1));
  await enqueue(kv, answer("ok", "b", 2));
  const r = await flush(kv, async (a) =>
    a.logId === "gone" ? { error: { message: "card not found", code: "P0001" } } : { error: null }
  );
  assert.deepEqual(r, { sent: 1, dropped: 1, left: 0 });
  assert.deepEqual(await pending(kv), []);
});

test("a send that throws counts as a network failure", async () => {
  const kv = memory();
  await enqueue(kv, answer("l1", "a", 1));
  const r = await flush(kv, async () => {
    throw new TypeError("Failed to fetch");
  });
  assert.deepEqual(r, { sent: 0, dropped: 0, left: 1 });
});
