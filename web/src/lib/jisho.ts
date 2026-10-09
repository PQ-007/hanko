// Dictionary auto-fill via Jisho's public API (same endpoint the extension's
// background script uses). Unofficial but widely used; on failure we just
// return blanks so the caller can fall back to manual entry.
import { compactGloss } from "./gloss.ts";

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
  // Jisho's WAF 403s the bare default User-Agent Node's fetch sends ("node") —
  // a dead giveaway for an unmodified script. Any non-default UA clears it.
  const res = await fetch(url, {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; Hanko/1.0)" },
  });
  if (!res.ok) throw new Error(`Lookup failed (${res.status})`);
  return parseJisho(await res.json(), term);
}

interface JishoWriting {
  word?: string;
  reading?: string;
}

interface JishoEntry {
  slug?: string;
  japanese?: JishoWriting[];
  senses?: { english_definitions?: string[] }[];
}

/**
 * Jisho's results → dictionary form, reading and a short meaning: the first
 * three senses, compacted by compactGloss.
 *
 * The entry and writing are chosen to keep `term` as typed when Jisho knows
 * it: Jisho lists an entry under its most common spelling, so the first
 * entry's first writing would swap a rarer kanji the user deliberately entered
 * (籠る, 附属) for the common one (篭る, 付属). Only when no entry has `term` as
 * a writing — a conjugated form like 食べました — is the first entry's main
 * writing used, which is what turns it into 食べる.
 *
 * Mirrored by `parseJisho` in mobile/lib/core/dictionary.dart.
 */
export function parseJisho(data: unknown, term = ""): LookupResult {
  const entries = ((data as { data?: JishoEntry[] } | null)?.data ?? []) as JishoEntry[];
  let entry = entries[0];
  if (!entry) return { word: "", reading: "", meaning: "" };

  let jp: JishoWriting = entry.japanese?.[0] ?? {};
  if (term) {
    for (const e of entries) {
      const exact = e.japanese?.find((w) => w.word === term);
      if (exact) {
        entry = e;
        jp = exact;
        break;
      }
    }
  }
  const reading: string = jp.reading ?? "";
  // Dictionary form: the kanji writing, or the slug, or the reading (kana words).
  const word: string = jp.word ?? entry.slug ?? reading ?? "";

  const meaning: string = compactGloss(
    (entry.senses ?? [])
      .slice(0, 3)
      .map((s) => (s.english_definitions ?? []).join(", "))
      .join("; ")
  );

  return { word, reading, meaning };
}
