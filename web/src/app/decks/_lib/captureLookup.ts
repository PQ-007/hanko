import { lookupMatches } from "./segment.ts";

// Looking up the words picked from a photo: a port of mobile's
// capture_lookup.dart, with the network injected so it's testable — the
// dictionary form, reading, English and Mongolian when Jisho recognises the
// word, the term as photographed with blank fields when it doesn't.

export interface CaptureItem {
  term: string;
  reading: string;
  meaning: string;
  meaningMn: string;
  /** False when the dictionary had nothing that matched. */
  found: boolean;
}

export interface LookupDeps {
  lookup: (term: string) => Promise<{ word: string; reading: string; meaning: string } | null>;
  translate: (text: string) => Promise<string>;
  onProgress?: (done: number, total: number) => void;
}

/** At most this many lookups at once: a page of thirty words shouldn't be a burst of thirty to a free API. */
const CONCURRENCY = 4;

/** Every chosen term as an item; two surface forms of one word (食べた, 食べます) collapse into one, in order. */
export async function resolveCapture(terms: string[], deps: LookupDeps): Promise<CaptureItem[]> {
  const results: (CaptureItem | null)[] = terms.map(() => null);
  let next = 0;
  let done = 0;
  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, terms.length) }, async () => {
      while (next < terms.length) {
        const i = next++;
        results[i] = await resolveOne(terms[i], deps);
        deps.onProgress?.(++done, terms.length);
      }
    })
  );
  const seen = new Set<string>();
  return results.filter((r): r is CaptureItem => !!r && !seen.has(r.term) && !!seen.add(r.term));
}

async function resolveOne(term: string, deps: LookupDeps): Promise<CaptureItem> {
  const r = await deps.lookup(term).catch(() => null);
  if (!r || !lookupMatches(term, r.word)) return { term, reading: "", meaning: "", meaningMn: "", found: false };
  const mn = r.meaning ? await deps.translate(r.meaning).catch(() => "") : "";
  return {
    term: r.word,
    reading: r.reading && r.reading !== r.word ? r.reading : "",
    meaning: r.meaning,
    meaningMn: mn,
    found: true,
  };
}
