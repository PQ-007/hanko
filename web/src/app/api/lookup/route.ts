import { NextResponse } from "next/server";
import { lookupWords } from "@/lib/jisho";
import { callerKey, takeToken } from "@/lib/rateLimit";

// GET /api/lookup?term=... -> { word, reading, meaning, results }
// Auto-fills the dictionary form + reading/meaning when adding a word.
// `results` is up to five matches, the first being the same as the top-level
// fields; the web's add-word dialog lists them. Older callers (extension,
// mobile) read only the top-level fields, so it is additive.
//
// Unauthenticated on purpose: the extension and the mobile app both call it,
// and neither has a cookie session here. That makes it an open proxy in front
// of Jisho unless it is throttled, which is what the bucket below is for. See
// rateLimit.ts for what this does and does not defend against.
//
// 30 up front, then 1/s sustained. A person adding words by hand types one
// lookup every few seconds and will never see this; a script will.
const BURST = 30;
const PER_SECOND = 1;

export async function GET(request: Request) {
  const term = new URL(request.url).searchParams.get("term")?.trim();
  if (!term) {
    return NextResponse.json({ error: "Missing term" }, { status: 400 });
  }

  if (!takeToken(callerKey(request), BURST, PER_SECOND)) {
    return NextResponse.json(
      { error: "Too many lookups" },
      // Retry-After is what makes this actionable rather than just a wall.
      { status: 429, headers: { "Retry-After": "1" } }
    );
  }

  try {
    const results = await lookupWords(term);
    const best = results[0] ?? { word: "", reading: "", meaning: "" };
    return NextResponse.json({ ...best, results });
  } catch {
    // Don't fail the UX over a dictionary outage.
    return NextResponse.json({ word: "", reading: "", meaning: "", results: [] });
  }
}
