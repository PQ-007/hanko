"use client";

import type { AudioDeck } from "./audioDeck";
import { kv } from "./offlineStore";

// Where audio decks live in the browser: the built MP3 and its cues in
// IndexedDB (offlineStore's database, so signing out clears them with the
// rest), and each speech clip in the Cache Storage under hanko-tts — a
// rebuild, or a word shared by two decks, costs no new request.

const CLIPS = "hanko-tts";
/** A spoken word or meaning is a few KB; anything far bigger isn't a clip. */
const MAX_BYTES = 512 * 1024;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** The speech clip for `text`, or null if it can't be had (offline and not kept, or refused). */
export async function fetchClip(text: string, lang: "ja" | "en"): Promise<Uint8Array | null> {
  const url = `/api/tts?lang=${lang}&text=${encodeURIComponent(text)}`;
  let cache: Cache | null = null;
  try {
    cache = await caches.open(CLIPS);
    const hit = await cache.match(url);
    if (hit) return new Uint8Array(await hit.arrayBuffer());
  } catch {}
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await fetch(url);
      if (res.status === 429) {
        await sleep(1000 * (Number(res.headers.get("Retry-After")) || 2));
        continue;
      }
      if (!res.ok || !(res.headers.get("content-type") ?? "").includes("audio")) return null;
      const bytes = new Uint8Array(await res.clone().arrayBuffer());
      if (bytes.length > MAX_BYTES) return null;
      cache?.put(url, res).catch(() => {});
      return bytes;
    } catch {
      return null;
    }
  }
  return null;
}

const key = (deckId: string) => `audio:${deckId}`;

export function loadAudioDeck(deckId: string): Promise<AudioDeck | undefined> {
  return kv.get<AudioDeck>(key(deckId));
}

export function saveAudioDeck(deck: AudioDeck): Promise<void> {
  return kv.set(key(deck.deckId), deck);
}

export function deleteAudioDeck(deckId: string): Promise<void> {
  return kv.del(key(deckId));
}
