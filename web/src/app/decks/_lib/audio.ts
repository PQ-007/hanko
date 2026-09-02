"use client";

import type { Word } from "@/lib/types";
import { supabase } from "./db";
import { T } from "./strings";

// Play a word's pronunciation, generating it on first use.
//
// The storage bucket is private, so playback is always: ensure an object
// exists at words.audio_path, then mint a short-lived signed URL for it.
//
// Returns the path it played, or null if nothing could be played. Callers
// compare that against the path they started with to learn whether generation
// happened — TTS is the expensive half of this (the route re-synthesizes on
// every POST, it does not short-circuit on an existing file), so a caller
// holding a stale row must be able to record the new path rather than ask for
// it a second time.
export async function playWordAudio(
  word: Pick<Word, "id" | "audio_path">
): Promise<string | null> {
  let path = word.audio_path;
  if (!path) {
    const res = await fetch(`/api/words/${word.id}/audio`, { method: "POST" });
    if (!res.ok) {
      alert((await res.json().catch(() => null))?.error ?? T.audioFailed);
      return null;
    }
    path = (await res.json()).audio_path as string;
  }
  if (!path) return null;
  const { data } = await supabase.storage.from("word-audio").createSignedUrl(path, 60);
  if (data?.signedUrl) new Audio(data.signedUrl).play();
  return path;
}
