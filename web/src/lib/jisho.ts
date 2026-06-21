// Dictionary auto-fill via Jisho's public API (same endpoint the extension's
// background script uses). Unofficial but widely used; on failure we just
// return blanks so the caller can fall back to manual entry.
export interface LookupResult {
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
  if (!entry) return { reading: "", meaning: "" };

  const jp = entry.japanese?.[0] ?? {};
  const reading: string = jp.reading ?? "";

  const meaning: string = (entry.senses ?? [])
    .slice(0, 3)
    .map((s: { english_definitions?: string[] }) =>
      (s.english_definitions ?? []).join(", ")
    )
    .filter(Boolean)
    .join("; ");

  return { reading, meaning };
}
