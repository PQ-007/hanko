// Dictionary auto-fill via Jisho's public API (same endpoint the extension's
// background script uses). Unofficial but widely used; on failure we just
// return blanks so the caller can fall back to manual entry.
export interface LookupResult {
  // The dictionary / base form (普通形) of the word — Jisho deinflects, so a
  // conjugated query like 担っています resolves to 担う here.
  word: string;
  reading: string;
  meaning: string;
}

export async function lookupWord(term: string): Promise<LookupResult> {
  const url = `https://jisho.org/api/v1/search/words?keyword=${encodeURIComponent(
    term
  )}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Lookup failed (${res.status})`);
  const data = await res.json();
  const entry = data?.data?.[0];
  if (!entry) return { word: "", reading: "", meaning: "" };

  const jp = entry.japanese?.[0] ?? {};
  const reading: string = jp.reading ?? "";
  // Dictionary form: the kanji writing, or the slug, or the reading (kana words).
  const word: string = jp.word ?? entry.slug ?? reading ?? "";

  const meaning: string = (entry.senses ?? [])
    .slice(0, 3)
    .map((s: { english_definitions?: string[] }) =>
      (s.english_definitions ?? []).join(", ")
    )
    .filter(Boolean)
    .join("; ");

  return { word, reading, meaning };
}
