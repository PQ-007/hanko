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
  let result = data[0]
    .map((seg: unknown[]) => (Array.isArray(seg) ? seg[0] : ""))
    .filter(Boolean)
    .join("")
    .trim();

  // Dictionary meanings are synonym lists ("careful, cautious, prudent") and
  // Google often maps several synonyms to the same Mongolian word, yielding
  // "болгоомжтой, болгоомжтой, …" — keep each item once.
  if (word.includes(",")) result = dedupeList(result);

  if (result) cache.set(word, result);
  return result;
}

function dedupeList(text: string): string {
  const parts = text.split(",").map((s) => s.trim()).filter(Boolean);
  if (parts.length < 2) return text;
  const seen = new Set<string>();
  const unique = parts.filter((p) => {
    const key = p.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return unique.join(", ");
}
