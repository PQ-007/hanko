// English -> Mongolian translation via the unofficial Google Translate endpoint
// (same one used for TTS). No API key required; "mn" is supported. Runs
// server-side only. Results are cached in-memory; meaning_mn is also persisted
// in the DB, so each word is only ever translated once.

const cache = new Map<string, string>();

export async function translateToMongolian(text: string): Promise<string> {
  const word = text.trim();
  if (!word) return "";
  if (cache.has(word)) return cache.get(word)!;

  const url =
    "https://translate.googleapis.com/translate_a/single" +
    `?client=gtx&sl=auto&tl=mn&dt=t&q=${encodeURIComponent(word)}`;
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
  const result = data[0]
    .map((seg: unknown[]) => (Array.isArray(seg) ? seg[0] : ""))
    .filter(Boolean)
    .join("")
    .trim();

  if (result) cache.set(word, result);
  return result;
}
