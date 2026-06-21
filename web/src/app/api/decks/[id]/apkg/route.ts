import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { loadDeckWithWords, sanitizeFilename, sanitizeTag, frontText, backText } from "@/lib/decks";
import { buildApkg, type ApkgNote } from "@/lib/anki/apkg";

// sql.js (wasm), node crypto, and fs require the Node.js runtime.
export const runtime = "nodejs";

// POST /api/decks/[id]/apkg -> a real Anki .apkg package (binary download).
export async function POST(
  _req: Request,
  ctx: RouteContext<"/api/decks/[id]/apkg">
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

  const supabase = await createClient();
  const tag = sanitizeTag(deck.name);

  const notes: ApkgNote[] = [];
  for (const w of words) {
    const note: ApkgNote = {
      guidSeed: w.id, // stable: re-export updates the same card
      front: frontText(w),
      back: backText(w).replace(/\n/g, "<br>"),
      tags: tag ? [tag] : [],
    };

    if (w.audio_path) {
      const { data: blob } = await supabase.storage
        .from("word-audio")
        .download(w.audio_path);
      if (blob) {
        note.audio = {
          filename: `vocabdecks-${w.id}.mp3`,
          bytes: new Uint8Array(await blob.arrayBuffer()),
        };
      }
    }
    notes.push(note);
  }

  const apkg = await buildApkg(deck.name, notes);

  return new NextResponse(apkg as BodyInit, {
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Disposition": `attachment; filename="${sanitizeFilename(
        deck.name
      )}.apkg"`,
    },
  });
}
