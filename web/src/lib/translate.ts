import { translateViaBolorToli } from "@/lib/bolortoli";

// English -> Mongolian translation. Runs server-side only.
//
// Provider:
//   - default: Google Translate (unofficial endpoint, no API key, supports "mn")
//   - bolor-toli: used automatically when BOLOR_TOLI_API_KEY is set (a proper
//     Mongolian dictionary, but it requires a key/quota)
//
// Results are cached in-memory; we also persist meaning_mn in the DB, so each
// word is only ever translated once.

const cache = new Map<string, string>();

export async function translateToMongolian(text: string): Promise<string> {
  const word = text.trim();
  if (!word) return "";
  if (cache.has(word)) return cache.get(word)!;

  const result = process.env.BOLOR_TOLI_API_KEY
    ? await translateViaBolorToli(word)
    : await translateViaGoogle(word);

  if (result) cache.set(word, result);
  return result;
}

// Unofficial Google Translate endpoint (same one used for TTS). Returns the
// translated text, joining multi-sentence results.
async function translateViaGoogle(text: string): Promise<string> {
  const url =
    "https://translate.googleapis.com/translate_a/single" +
    `?client=gtx&sl=auto&tl=mn&dt=t&q=${encodeURIComponent(text)}`;
  const res = await fetch(url, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    },
  });
  if (!res.ok) throw new Error(`Google Translate ${res.status}`);
  const data = await res.json();
  // Shape: [[["translated","source",...], ...], ...]
  if (!Array.isArray(data?.[0])) return "";
  return data[0]
    .map((seg: unknown[]) => (Array.isArray(seg) ? seg[0] : ""))
    .filter(Boolean)
    .join("")
    .trim();
}
