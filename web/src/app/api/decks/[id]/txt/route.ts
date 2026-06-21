import { NextResponse } from "next/server";
import {
  loadDeckWithWords,
  sanitizeFilename,
  sanitizeTag,
  frontText,
} from "@/lib/decks";

// POST /api/decks/[id]/txt
// Tab-separated Anki import file (Front \t Back \t Tag), matching the
// extension's original .txt export so existing import instructions still apply.
export async function POST(
  _req: Request,
  ctx: RouteContext<"/api/decks/[id]/txt">
) {
  const { id } = await ctx.params;
  const result = await loadDeckWithWords(id);
  if (!result) {
    return NextResponse.json({ error: "Deck not found" }, { status: 404 });
  }
  const { deck, words } = result;
  if (words.length === 0) {
    return NextResponse.json({ error: "Deck has no words" }, { status: 400 });
  }

  const tag = sanitizeTag(deck.name);
  const lines = words.map((w) => {
    const back = (w.meaning ?? "").replace(/\t/g, " ").replace(/\n/g, "<br>");
    return [frontText(w), back, tag].join("\t");
  });

  return new NextResponse(lines.join("\n"), {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Disposition": `attachment; filename="${sanitizeFilename(
        deck.name
      )}.txt"`,
    },
  });
}
