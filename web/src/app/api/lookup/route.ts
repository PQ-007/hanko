import { NextResponse } from "next/server";
import { lookupWord } from "@/lib/jisho";

// GET /api/lookup?term=... -> { reading, meaning }
// Auto-fills reading/meaning when adding a word on the site.
export async function GET(request: Request) {
  const term = new URL(request.url).searchParams.get("term")?.trim();
  if (!term) {
    return NextResponse.json({ error: "Missing term" }, { status: 400 });
  }
  try {
    return NextResponse.json(await lookupWord(term));
  } catch {
    // Don't fail the UX over a dictionary outage.
    return NextResponse.json({ reading: "", meaning: "" });
  }
}
