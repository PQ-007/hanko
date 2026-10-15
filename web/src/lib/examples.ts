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
  /** Tatoeba's reading of `ja`, "[私|わたし]は…" (0032); see parseFurigana. */
  furigana?: string;
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

/** The Japanese reading among a sentence's transcriptions, if it describes `ja`. */
function furiganaOf(list: unknown, ja: string): string | undefined {
  if (!Array.isArray(list)) return undefined;
  for (const t of list as Row[]) {
    if (!t || typeof t !== "object" || t.script !== "Hrkt") continue;
    const text = String(t.text ?? "").trim();
    if (text && plainOf(text) === ja) return text;
  }
  return undefined;
}

export interface RubyUnit {
  text: string;
  /** "" for text that needs none (kana, punctuation). */
  reading: string;
}

/**
 * Tatoeba's reading markup → units to draw: "[勉強|べん|きょう]は" →
 * 勉(べん) 強(きょう) は. One reading per kanji when the readings split
 * cleanly, else one over the whole word ("[今日|きょう]"). Null when the
 * markup is malformed.
 */
export function parseFurigana(markup: string): RubyUnit[] | null {
  const out: RubyUnit[] = [];
  let i = 0;
  while (i < markup.length) {
    const ch = markup[i];
    if (ch === "]") return null;
    if (ch !== "[") {
      out.push({ text: ch, reading: "" });
      i++;
      continue;
    }
    const end = markup.indexOf("]", i);
    if (end < 0) return null;
    const [base, ...readings] = markup.slice(i + 1, end).split("|");
    if (!base || base.includes("[") || readings.some((r) => !r)) return null;
    const chars = Array.from(base);
    if (readings.length > 1 && readings.length === chars.length) {
      chars.forEach((c, k) => out.push({ text: c, reading: readings[k] === c ? "" : readings[k] }));
    } else {
      const reading = readings.join("");
      out.push({ text: base, reading: reading === base ? "" : reading });
    }
    i = end + 1;
  }
  return out;
}

/** The plain sentence a reading describes ("" when malformed). */
export function plainOf(markup: string): string {
  return parseFurigana(markup)?.map((u) => u.text).join("") ?? "";
}

/**
 * What to draw for `ja`: its reading's units when `furigana` describes it
 * exactly, else one unit per character with no reading — a sentence the user
 * edited or wrote has no reading to trust.
 */
export function rubyUnits(ja: string, furigana?: string | null): RubyUnit[] {
  const units = furigana ? parseFurigana(furigana) : null;
  if (units && units.map((u) => u.text).join("") === ja) return units;
  return Array.from(ja, (c) => ({ text: c, reading: "" }));
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
    const furigana = furiganaOf(s.transcriptions, ja);

    const len = ja.length;
    const shape = len < 8 ? 8 - len : len > 24 ? len - 24 : 0;
    const score = (exact ? 0 : 10) + shape;
    if (score < bestScore) {
      best = furigana ? { ja, en, furigana } : { ja, en };
      bestScore = score;
    }
  }
  return best;
}

/**
 * Where `sentence` uses `term` — the word itself, or, conjugated, its stem
 * (食べ for 食べる): [start, end), or null. Same rule as example_line.dart.
 */
export function highlightRange(sentence: string, term: string): [number, number] | null {
  const t = term.trim();
  if (!t) return null;
  let at = sentence.indexOf(t);
  let len = t.length;
  if (at < 0) {
    const stem = wordStem(t);
    at = sentence.indexOf(stem);
    len = stem.length;
  }
  return at < 0 ? null : [at, at + len];
}

/** `sentence` cut around highlightRange. */
export function highlightParts(sentence: string, term: string): { before: string; mark: string; after: string } {
  const r = highlightRange(sentence, term);
  if (!r) return { before: sentence, mark: "", after: "" };
  return { before: sentence.slice(0, r[0]), mark: sentence.slice(r[0], r[1]), after: sentence.slice(r[1]) };
}

/** "Tatoeba has nothing for this word" is remembered too, but retried after this long — the corpus grows. */
export const RETRY_NONE_AFTER_MS = 30 * 24 * 3600 * 1000;

// v2: answers now carry the reading; v1 entries (without) are asked again.
const STORE_PREFIX = "hanko.example2:";
const found = new Map<string, Example | null>();
const inFlight = new Map<string, Promise<Example | null>>();

/** This browser's copy of an earlier answer (like mobile's on-disk cache): a repeated word is instant. */
function remembered(t: string): Example | null | undefined {
  try {
    const raw = window.localStorage.getItem(STORE_PREFIX + t);
    if (!raw) return undefined;
    const j = JSON.parse(raw) as { ja?: string; en?: string; furigana?: string; at?: number };
    if (j.ja && j.en) return { ja: j.ja, en: j.en, ...(j.furigana ? { furigana: j.furigana } : {}) };
    return typeof j.at === "number" && Date.now() - j.at < RETRY_NONE_AFTER_MS ? null : undefined;
  } catch {
    return undefined;
  }
}

function remember(t: string, e: Example | null) {
  try {
    window.localStorage.setItem(STORE_PREFIX + t, JSON.stringify({ ...e, at: Date.now() }));
  } catch {
    // No storage (private window, node tests): the in-memory copy still works.
  }
}

/**
 * The sentence for `term`, or null when there's no good one or the request
 * failed. Answers are remembered in this tab and in this browser; a failure
 * isn't, so it's retried. Two callers asking at once share one request.
 */
export function findExample(term: string, fetcher: typeof fetch = fetch): Promise<Example | null> {
  const t = term.trim();
  if (!t) return Promise.resolve(null);
  if (found.has(t)) return Promise.resolve(found.get(t)!);
  const kept = typeof window === "undefined" ? undefined : remembered(t);
  if (kept !== undefined) {
    found.set(t, kept);
    return Promise.resolve(kept);
  }
  const running = inFlight.get(t);
  if (running) return running;
  const p = ask(t, fetcher).finally(() => inFlight.delete(t));
  inFlight.set(t, p);
  return p;
}

async function ask(t: string, fetcher: typeof fetch): Promise<Example | null> {
  const url = new URL("https://api.tatoeba.org/unstable/sentences");
  for (const [k, v] of Object.entries({
    lang: "jpn",
    q: t,
    sort: "relevance",
    "trans:lang": "eng",
    showtrans: "matching",
    limit: "50",
    include: "transcriptions",
  })) {
    url.searchParams.set(k, v);
  }
  try {
    const res = await fetcher(url.toString());
    if (!res.ok) return null; // not remembered: a failure should be retried
    const body = await res.json();
    const picked = pickExample(t, body?.data);
    found.set(t, picked);
    if (typeof window !== "undefined") remember(t, picked);
    return picked;
  } catch {
    return null;
  }
}
