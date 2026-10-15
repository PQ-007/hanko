import { NextResponse } from "next/server";
import { synthesizeMp3 } from "@/lib/tts";
import { clientForRequest } from "@/lib/supabase/bearer";
import { takeToken } from "@/lib/rateLimit";

export const runtime = "nodejs";

// GET /api/tts?lang=ja|en&text=… → audio/mpeg
//
// Speech clips for audio decks (decks/_lib/audioDeck.ts). The browser can't
// read Google's voice itself — the endpoint sends no CORS headers — so this
// fetches it, through the same synthesizeMp3() the word-audio route uses.
//
// Signed-in callers only, and throttled per user, so it can't become an open
// proxy in front of Google. A deck of a hundred words with sentences is a few
// hundred clips, fetched three at a time: 400 up front, then 5 a second.
// The answer never changes for a given text, so the browser may keep it.
const BURST = 400;
const PER_SECOND = 5;
const LANGS = new Set(["ja", "en"]);

export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const lang = params.get("lang") ?? "";
  const text = (params.get("text") ?? "").trim();
  if (!LANGS.has(lang) || !text || text.length > 200) {
    return NextResponse.json({ error: "bad request" }, { status: 400 });
  }

  const supabase = await clientForRequest(request);
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  if (!takeToken(`tts:${user.id}`, BURST, PER_SECOND)) {
    return NextResponse.json({ error: "too many" }, { status: 429, headers: { "Retry-After": "2" } });
  }

  try {
    const mp3 = await synthesizeMp3(text, lang);
    return new NextResponse(new Uint8Array(mp3), {
      headers: { "Content-Type": "audio/mpeg", "Cache-Control": "private, max-age=2592000, immutable" },
    });
  } catch {
    return NextResponse.json({ error: "speech unavailable" }, { status: 502 });
  }
}
