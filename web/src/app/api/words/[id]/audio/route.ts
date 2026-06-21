import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { synthesizeMp3 } from "@/lib/tts";
import type { Word } from "@/lib/types";

export const runtime = "nodejs";

// POST /api/words/[id]/audio
// Generates pronunciation audio for a word (TTS), stores it in the private
// word-audio bucket under "<user_id>/<word_id>.mp3", records the path on the
// word, and returns { audio_path }. Idempotent: re-running overwrites.
export async function POST(
  _req: Request,
  ctx: RouteContext<"/api/words/[id]/audio">
) {
  const { id } = await ctx.params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { data: word } = await supabase
    .from("words")
    .select("*")
    .eq("id", id)
    .single();
  if (!word) {
    return NextResponse.json({ error: "Word not found" }, { status: 404 });
  }
  const w = word as Word;

  // Prefer the reading (kana) for pronunciation, fall back to the term.
  const speakText = (w.reading || w.term).trim();
  if (!speakText) {
    return NextResponse.json({ error: "Nothing to synthesize" }, { status: 400 });
  }

  let mp3: Uint8Array;
  try {
    mp3 = await synthesizeMp3(speakText, "ja");
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "TTS failed" },
      { status: 502 }
    );
  }

  const path = `${user.id}/${w.id}.mp3`;
  const { error: upErr } = await supabase.storage
    .from("word-audio")
    .upload(path, mp3, { contentType: "audio/mpeg", upsert: true });
  if (upErr) {
    return NextResponse.json({ error: upErr.message }, { status: 500 });
  }

  await supabase.from("words").update({ audio_path: path }).eq("id", w.id);

  return NextResponse.json({ audio_path: path });
}
