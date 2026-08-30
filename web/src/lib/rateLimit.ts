// A token bucket, keyed by caller. Deliberately in-process and dependency-free.
//
// What it is for: /api/lookup takes no auth and proxies Jisho, so on a public
// URL it is an open proxy — anyone can point a script at it and spend Hanko's
// reputation with Jisho rather than their own. It is also the mobile app's
// dictionary, so it cannot simply be locked behind a session.
//
// What it is NOT: protection against a distributed caller. The counters live
// in one server process, so a deployment with several instances enforces the
// limit per instance, and a serverless one may reset it whenever a cold start
// happens. That is an honest limit of solving this without Redis, and it is
// still the difference between "trivially abusable" and "not worth bothering
// with". Revisit if this ever runs on more than one instance.

interface Bucket {
  tokens: number;
  updatedAt: number;
}

const buckets = new Map<string, Bucket>();

// Swept lazily rather than on a timer: a setInterval would keep a serverless
// instance alive, and the map only grows while requests are arriving anyway.
const SWEEP_EVERY = 500;
let sinceSweep = 0;

function sweep(now: number, idleMs: number) {
  for (const [key, bucket] of buckets) {
    if (now - bucket.updatedAt > idleMs) buckets.delete(key);
  }
}

/**
 * Consumes one token for `key`. Returns false when the caller is over budget.
 *
 * `capacity` is the burst allowance; `refillPerSec` the sustained rate.
 */
export function takeToken(
  key: string,
  capacity: number,
  refillPerSec: number
): boolean {
  const now = Date.now();

  if (++sinceSweep >= SWEEP_EVERY) {
    sinceSweep = 0;
    sweep(now, (capacity / refillPerSec) * 1000 * 10);
  }

  const bucket = buckets.get(key) ?? { tokens: capacity, updatedAt: now };
  // Refill for the elapsed time before spending, so a caller that waits gets
  // its allowance back without any scheduled work.
  bucket.tokens = Math.min(
    capacity,
    bucket.tokens + ((now - bucket.updatedAt) / 1000) * refillPerSec
  );
  bucket.updatedAt = now;

  if (bucket.tokens < 1) {
    buckets.set(key, bucket);
    return false;
  }
  bucket.tokens -= 1;
  buckets.set(key, bucket);
  return true;
}

/**
 * Best-effort caller identity. `x-forwarded-for` is spoofable in general, but
 * on a platform that sets it (Vercel, most reverse proxies) the left-most
 * entry is the real peer. Everything unattributable shares one bucket, which
 * is the safe direction to fail.
 */
export function callerKey(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  return forwarded?.split(",")[0]?.trim() || request.headers.get("x-real-ip") || "anonymous";
}
