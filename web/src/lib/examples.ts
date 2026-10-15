// Example sentences for words, from Tatoeba — a free, keyless corpus of
// Japanese sentences with human English translations (CC BY 2.0 FR). Called
// straight from the browser (Tatoeba answers CORS `*`), so there is no route
// of ours in between and no new open proxy.
//
// A port of mobile/lib/features/audio/example_sentences.dart: same picking
// rules, pinned by the same cases (examples.test.ts / example_sentences_test.dart),
// so both clients suggest the same sentence for a word.

export interface Example {
  ja: string;
  en: string;
}

/** Japanese sentences longer than this are hard to take in at a glance. */
export const MAX_SENTENCE_CHARS = 32;

/** Translations longer than this drag. */
export const MAX_TRANSLATION_CHARS = 140;

const KANJI = /[㐀-䶿一-鿿々]/;
const HIRAGANA = /^[ぁ-ゟ]$/;

const isKanji = (ch: string) => ch !== "" && KANJI.test(ch);

/**
 * The part of `term` that stays put when it's conjugated: 食べる → 食べ
 * (食べた, 食べます), 担う → 担 (担った), 勉強する → 勉強. A term with no
 * kanji or no trailing kana is its own stem.
 */
export function wordStem(term: string): string {
  if (term.length > 2 && term.endsWith("する")) return term.slice(0, -2);
  if (term.length >= 2 && KANJI.test(term) && HIRAGANA.test(term[term.length - 1])) {
    return term.slice(0, -1);
  }
  return term;
}

/**
 * Whether `sentence` uses `s` as a word rather than as part of a longer kanji
 * compound: a kanji edge of `s` must not touch another kanji, so 群 is found
 * in 羊の群を見た but not in 抜群, and 担 (担う) not in 担当.
 */
export function usesAsWord(sentence: string, s: string): boolean {
  if (!s) return false;
  for (let i = sentence.indexOf(s); i >= 0; i = sentence.indexOf(s, i + 1)) {
    const before = i > 0 ? sentence[i - 1] : "";
    const end = i + s.length;
    const after = end < sentence.length ? sentence[end] : "";
    if (isKanji(s[0]) && isKanji(before)) continue;
    if (isKanji(s[s.length - 1]) && isKanji(after)) continue;
    return true;
  }
  return false;
}

type Row = Record<string, unknown>;

/** The first usable English translation, a direct one if there is one. */
function translationOf(list: unknown): string | null {
  if (!Array.isArray(list)) return null;
  let indirect: string | null = null;
  for (const t of list as Row[]) {
    if (!t || typeof t !== "object" || t.lang !== "eng" || t.is_unapproved === true) continue;
    const text = String(t.text ?? "").trim();
    if (!text || text.length > MAX_TRANSLATION_CHARS) continue;
    if (t.is_direct !== false) return text;
    indirect ??= text;
  }
  return indirect;
}

/**
 * The best sentence for `term` out of Tatoeba's results (most relevant
 * first): approved, with an English translation, short, and using the word
 * itself — the exact form preferred over a conjugated one, a mid-length
 * sentence over a bare one-word "食べる。".
 */
export function pickExample(term: string, data: unknown): Example | null {
  if (!Array.isArray(data)) return null;
  const stem = wordStem(term);
  let best: Example | null = null;
  let bestScore = Infinity;
  for (const s of data as Row[]) {
    if (!s || typeof s !== "object" || s.is_unapproved === true) continue;
    const ja = String(s.text ?? "").trim();
    if (!ja || ja.length > MAX_SENTENCE_CHARS) continue;
    const exact = usesAsWord(ja, term);
    if (!exact && (stem === term || !usesAsWord(ja, stem))) continue;

    const en = translationOf(s.translations);
    if (en === null) continue;

    const len = ja.length;
    const shape = len < 8 ? 8 - len : len > 24 ? len - 24 : 0;
    const score = (exact ? 0 : 10) + shape;
    if (score < bestScore) {
      best = { ja, en };
      bestScore = score;
    }
  }
  return best;
}

/**
 * `sentence` cut so the first use of `term` — or, conjugated, its stem
 * (食べ for 食べる) — is `mark`. Same rule as example_line.dart.
 */
export function highlightParts(sentence: string, term: string): { before: string; mark: string; after: string } {
  const t = term.trim();
  let at = t ? sentence.indexOf(t) : -1;
  let len = t.length;
  if (at < 0 && t) {
    const stem = wordStem(t);
    at = sentence.indexOf(stem);
    len = stem.length;
  }
  if (at < 0) return { before: sentence, mark: "", after: "" };
  return { before: sentence.slice(0, at), mark: sentence.slice(at, at + len), after: sentence.slice(at + len) };
}

const found = new Map<string, Example | null>();

/** The sentence for `term`, or null when there's no good one or the request failed. */
export async function findExample(term: string, fetcher: typeof fetch = fetch): Promise<Example | null> {
  const t = term.trim();
  if (!t) return null;
  if (found.has(t)) return found.get(t)!;
  const url = new URL("https://api.tatoeba.org/unstable/sentences");
  for (const [k, v] of Object.entries({
    lang: "jpn",
    q: t,
    sort: "relevance",
    "trans:lang": "eng",
    showtrans: "matching",
    limit: "50",
  })) {
    url.searchParams.set(k, v);
  }
  try {
    const res = await fetcher(url.toString());
    if (!res.ok) return null; // not remembered: a failure should be retried
    const body = await res.json();
    const picked = pickExample(t, body?.data);
    found.set(t, picked);
    return picked;
  } catch {
    return null;
  }
}
