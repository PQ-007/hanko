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

// ---------------------------------------------------------------------------
// Batch search, for populating the Monster Hunt distractor cache
// (supabase/migrations/0015_distractor_cache.sql). Different job from
// lookupWord: that resolves one known term to its reading/meaning; this pulls
// a page of *candidate* words to draw wrong-answer options from.
// ---------------------------------------------------------------------------

export interface CandidateWord {
  word: string;
  reading: string;
  meaning: string;
  // Jisho's own granular tags (e.g. "Godan verb with 'u' ending",
  // "I-adjective"), not yet bucketed — coarsePartOfSpeech() does that.
  partsOfSpeech: string[];
}

// Validated live against Jisho before writing this: `#common` reliably
// returns real common words with usable parts_of_speech in the response;
// combining it with a second tag like `#noun` returns identical results to
// `#common` alone, and an actually-unrecognized tag (`#zzznotarealtag`)
// returns zero — meaning Jisho is not narrowing by an arbitrary POS tag in
// the request, it's just matching `#common`. So filtering happens on the
// *response* data (coarsePartOfSpeech below), never by assuming a POS tag
// works in the query string. `#jlpt-n5`..`#jlpt-n1` genuinely do narrow
// results (confirmed different word sets per level), so rotating through
// them alongside `#common` is what gives the cache variety across pages
// rather than the same 20 words every time.
const BATCH_TAGS = ["#common", "#jlpt-n5", "#jlpt-n4", "#jlpt-n3"] as const;

export async function searchCandidateWords(
  page: number
): Promise<CandidateWord[]> {
  const tag = BATCH_TAGS[page % BATCH_TAGS.length];
  const pageNum = Math.floor(page / BATCH_TAGS.length) + 1;
  const url = `https://jisho.org/api/v1/search/words?keyword=${encodeURIComponent(
    tag
  )}&page=${pageNum}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Batch search failed (${res.status})`);
  const data = await res.json();

  const out: CandidateWord[] = [];
  for (const entry of data?.data ?? []) {
    const jp = entry.japanese?.[0] ?? {};
    const word: string = jp.word ?? entry.slug ?? jp.reading ?? "";
    if (!word) continue;
    const reading: string = jp.reading ?? "";
    const meaning: string = (entry.senses ?? [])
      .slice(0, 2)
      .map((s: { english_definitions?: string[] }) =>
        (s.english_definitions ?? []).join(", ")
      )
      .filter(Boolean)
      .join("; ");
    const partsOfSpeech: string[] = entry.senses?.[0]?.parts_of_speech ?? [];
    if (!meaning) continue;
    out.push({ word, reading, meaning, partsOfSpeech });
  }
  return out;
}

// Buckets Jisho's granular part-of-speech tags down to something small enough
// to usefully match on ("same part of speech" as a distractor heuristic).
// Falls back to "Other" rather than throwing — an unrecognized tag just means
// a coarser match, never a broken quiz.
export function coarsePartOfSpeech(tags: string[]): string {
  const joined = tags.join(" ").toLowerCase();
  // Noun checked first, not verb: common Japanese words like 結果/仕事 are
  // tagged ['Noun', 'Suru verb', ...] — the noun+する pattern, genuinely both,
  // but their dictionary-form identity is the noun (結果 = "result"), and a
  // beginner would reach for them as nouns. Checking "verb" first (the
  // original order here, before this was validated against real Jisho
  // responses) miscategorized roughly 15-20% of common words as verbs.
  if (joined.includes("noun")) return "Noun";
  if (joined.includes("verb")) return "Verb";
  if (joined.includes("i-adjective") || joined.includes("na-adjective") || joined.includes("adjective"))
    return "Adjective";
  if (joined.includes("adverb")) return "Adverb";
  return "Other";
}
