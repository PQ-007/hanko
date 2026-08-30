import { NextResponse } from "next/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import { serviceClient } from "@/lib/supabase/service";
import { coarsePartOfSpeech, searchCandidateWords } from "@/lib/jisho";

// A plain server-side client for reads — NOT web/src/lib/supabase/client.ts,
// which is "use client" (createBrowserClient) and has no place in a route
// handler; it also carries no cookie/session, so under the old
// authenticated-only RLS policy every read would have silently resolved as
// the anon role and been rejected. The cache is public reference data (see
// 0015_distractor_cache.sql), so the publishable key + a `using (true)`
// select policy is the right amount of access — no session needed either
// side.
function readClient(): SupabaseClient {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    (process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)!,
    { auth: { persistSession: false, autoRefreshToken: false } }
  );
}

export const runtime = "nodejs";

// GET /api/distractors?term=X&pos=Y -> { options: [{term, reading, meaning, closeness}] }
// Wrong-answer options for the Monster Hunt quiz. Public like /api/lookup —
// no user data involved, just dictionary words.
//
// Sourcing: read-through cache over live Jisho searches (see
// searchCandidateWords in @/lib/jisho and supabase/migrations/0015). The
// cache table starts empty and grows from real results; nothing here is a
// bulk-imported dataset.
const MIN_CANDIDATES = 6;
const MAX_JISHO_PAGES = 4;
const CLOSE_LENGTH_TOLERANCE = 2;

interface Candidate {
  term: string;
  reading: string | null;
  meaning: string;
  part_of_speech: string | null;
  term_length: number;
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const term = url.searchParams.get("term")?.trim();
  const pos = url.searchParams.get("pos")?.trim() || "Other";
  if (!term) {
    return NextResponse.json({ error: "Missing term" }, { status: 400 });
  }

  const db = readClient();

  let candidates = await readCache(db, pos);
  if (candidates.length < MIN_CANDIDATES) {
    candidates = await warmCache(db, pos, candidates);
  }

  const options = pickDistractors(term, pos, candidates);
  return NextResponse.json({ options });
}

async function readCache(
  db: SupabaseClient,
  pos: string
): Promise<Candidate[]> {
  const { data } = await db
    .from("distractor_cache")
    .select("term, reading, meaning, part_of_speech, term_length")
    .eq("part_of_speech", pos)
    .limit(60);
  return (data as Candidate[]) ?? [];
}

// Pulls a few pages of Jisho candidates, upserts anything matching the
// requested POS bucket into the cache (service-role, if configured), and
// returns the merged candidate set for this request even if the write is
// skipped. Stops early once enough same-POS candidates are found — no reason
// to keep hitting Jisho once the bucket has plenty.
async function warmCache(
  db: SupabaseClient,
  pos: string,
  existing: Candidate[]
): Promise<Candidate[]> {
  const svc = serviceClient();
  const seen = new Set(existing.map((c) => c.term));
  const matched: Candidate[] = [...existing];
  const toCache: Candidate[] = [];

  for (let page = 0; page < MAX_JISHO_PAGES; page++) {
    let batch: Awaited<ReturnType<typeof searchCandidateWords>>;
    try {
      batch = await searchCandidateWords(page);
    } catch {
      break; // Jisho hiccup — return whatever we already have, never 500.
    }
    for (const w of batch) {
      if (seen.has(w.word)) continue;
      seen.add(w.word);
      const bucket = coarsePartOfSpeech(w.partsOfSpeech);
      const row: Candidate = {
        term: w.word,
        reading: w.reading || null,
        meaning: w.meaning,
        part_of_speech: bucket,
        term_length: [...w.word].length,
      };
      toCache.push(row);
      if (bucket === pos) matched.push(row);
    }
    if (matched.length >= MIN_CANDIDATES) break;
  }

  if (svc && toCache.length > 0) {
    // Best-effort: a cache-write failure must never break the quiz, since
    // `matched` already has what this request needs regardless.
    await svc
      .from("distractor_cache")
      .upsert(toCache, { onConflict: "term,part_of_speech", ignoreDuplicates: true })
      .then(undefined, () => {});
  }

  return matched;
}

function pickDistractors(
  correctTerm: string,
  pos: string,
  candidates: Candidate[]
) {
  const correctLen = [...correctTerm].length;
  const pool = candidates.filter((c) => c.term !== correctTerm);

  const close = pool.filter(
    (c) =>
      c.part_of_speech === pos &&
      Math.abs(c.term_length - correctLen) <= CLOSE_LENGTH_TOLERANCE
  );
  const far = pool.filter((c) => !close.includes(c));

  const picked: Array<Candidate & { closeness: "close" | "far" }> = [];
  const take = (list: Candidate[], n: number, closeness: "close" | "far") => {
    const shuffled = [...list].sort(() => Math.random() - 0.5);
    for (const c of shuffled.slice(0, n)) picked.push({ ...c, closeness });
  };

  // Aim for 2 close + 1 far; widen from whichever pool has more if one side
  // is short, so a rare word still returns 3 options rather than failing.
  take(close, 2, "close");
  take(far, 3 - picked.length, "far");
  if (picked.length < 3) {
    const remaining = pool.filter((c) => !picked.some((p) => p.term === c.term));
    take(remaining, 3 - picked.length, "far");
  }

  return picked.map((c) => ({
    term: c.term,
    reading: c.reading,
    meaning: c.meaning,
    closeness: c.closeness,
  }));
}
