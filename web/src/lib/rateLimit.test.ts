import { test } from "node:test";
import assert from "node:assert/strict";
import { callerKey, takeToken } from "./rateLimit.ts";

test("a burst up to capacity is allowed, and the next call is not", () => {
  const key = `burst-${Math.random()}`;
  for (let i = 0; i < 5; i++) {
    assert.ok(takeToken(key, 5, 1), `call ${i + 1} should pass`);
  }
  assert.equal(takeToken(key, 5, 1), false, "call 6 is over budget");
});

test("callers are throttled independently", () => {
  const a = `a-${Math.random()}`;
  const b = `b-${Math.random()}`;
  assert.ok(takeToken(a, 1, 1));
  assert.equal(takeToken(a, 1, 1), false);
  assert.ok(takeToken(b, 1, 1), "b must not inherit a's exhaustion");
});

test("waiting refills the bucket", async () => {
  const key = `refill-${Math.random()}`;
  assert.ok(takeToken(key, 1, 50)); // 50/s -> a token back in 20ms
  assert.equal(takeToken(key, 1, 50), false);
  await new Promise((r) => setTimeout(r, 60));
  assert.ok(takeToken(key, 1, 50), "should have refilled while idle");
});

test("refill never exceeds capacity", async () => {
  const key = `cap-${Math.random()}`;
  assert.ok(takeToken(key, 2, 1000));
  await new Promise((r) => setTimeout(r, 30)); // would earn 30 tokens uncapped
  assert.ok(takeToken(key, 2, 1000));
  assert.ok(takeToken(key, 2, 1000));
  assert.equal(takeToken(key, 2, 1000), false, "burst is still only 2");
});

test("the caller key prefers the left-most forwarded address", () => {
  const req = new Request("https://x/y", {
    headers: { "x-forwarded-for": "203.0.113.7, 10.0.0.1" },
  });
  assert.equal(callerKey(req), "203.0.113.7");
});

test("an unattributable caller falls back to a shared bucket", () => {
  assert.equal(callerKey(new Request("https://x/y")), "anonymous");
});
