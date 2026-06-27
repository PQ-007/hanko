import { NextResponse } from "next/server";
import { lookupWord } from "@/lib/jisho";

// GET /api/lookup?term=... -> { word, reading, meaning }
// Auto-fills the dictionary form + reading/meaning when adding a word.
export async function GET(request: Request) {
  const term = new URL(request.url).searchParams.get("term")?.trim();
  if (!term) {
    return NextResponse.json({ error: "Missing term" }, { status: 400 });
  }
  try {
    return NextResponse.json(await lookupWord(term));
  } catch {
    // Don't fail the UX over a dictionary outage.
    return NextResponse.json({ word: "", reading: "", meaning: "" });
  }
}
