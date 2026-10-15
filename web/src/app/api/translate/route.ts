import { NextResponse } from "next/server";
import { translateToMongolian } from "@/lib/translate";

export const runtime = "nodejs";

// GET /api/translate?text=... -> { mongolian }
// English -> Mongolian via Google Translate (server-side, no key).
// Public endpoint (translation isn't user-specific) so the extension can call
// it too without auth.
// &sentence=1 keeps the translation whole (example sentences, 0031) instead
// of compacting it to a short gloss.
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const text = params.get("text")?.trim();
  if (!text) {
    return NextResponse.json({ error: "Missing text" }, { status: 400 });
  }
  // Same bound as words_example_len: a sentence, not a document.
  if (text.length > 500) {
    return NextResponse.json({ error: "Text too long" }, { status: 400 });
  }
  try {
    const mongolian = await translateToMongolian(text, { sentence: params.get("sentence") === "1" });
    return NextResponse.json({ mongolian });
  } catch (e) {
    return NextResponse.json(
      { mongolian: "", error: e instanceof Error ? e.message : "translate failed" },
      { status: 200 }
    );
  }
}
