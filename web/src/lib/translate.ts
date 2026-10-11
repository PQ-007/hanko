import { compactGloss, stripNotes } from "./gloss.ts";

// English -> Mongolian translation via Google Translate's keyless endpoints.
// No API key required; "mn" is supported. Runs server-side only. Results are
// cached in-memory; meaning_mn is also persisted in the DB, so each word is
// only ever translated once.
//
// Two endpoints, tried in order. translate.googleapis.com (client=gtx) — the
// one this used to call alone, and the one mobile still calls from the phone —
// answers every request from Node with a 429 "unusual traffic" page: it keys
// on Node's TLS fingerprint, not the headers (no User-Agent or header set
// helps; curl and Dart get 200 for the same URL). clients5.google.com
// (client=dict-chrome-ex, Chrome's dictionary extension) answers Node fine,
// so it goes first and gtx stays as the fallback.
//
// The output is compacted (compactGloss, see gloss.ts), like the English it is
// translated from.

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";

const cache = new Map<string, string>();

/**
 * dict-chrome-ex answers `[["translated", "en"]]` with sl=auto, or
 * `["translated"]` with a fixed source language; gtx answers
 * `[[["translated", "source", …], …], …]`, one segment per sentence.
 * Anything else is "".
 */
export function parseTranslation(data: unknown): string {
  if (!Array.isArray(data)) return "";
  const first = data[0];
  if (typeof first === "string") return first.trim();
  if (!Array.isArray(first)) return "";
  // dict-chrome-ex, sl=auto: [text, detectedLang]
  if (typeof first[0] === "string") return first[0].trim();
  // gtx: segments
  return first
    .map((seg: unknown) => (Array.isArray(seg) && typeof seg[0] === "string" ? seg[0] : ""))
    .join("")
    .trim();
}

const ENDPOINTS = [
  (q: string) => `https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=mn&q=${q}`,
  (q: string) => `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=mn&dt=t&q=${q}`,
];

export async function translateToMongolian(text: string): Promise<string> {
  const word = text.trim();
  if (!word) return "";
  if (cache.has(word)) return cache.get(word)!;

  const q = encodeURIComponent(stripNotes(word) || word);
  let lastError: unknown = null;
  for (const endpoint of ENDPOINTS) {
    try {
      const res = await fetch(endpoint(q), { headers: { "User-Agent": UA } });
      if (!res.ok) throw new Error(`Google Translate ${res.status}`);
      const result = compactGloss(parseTranslation(await res.json()));
      if (!result) continue;
      cache.set(word, result);
      return result;
    } catch (e) {
      lastError = e;
    }
  }
  if (lastError) throw lastError;
  return "";
}
