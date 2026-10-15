import { audioFrames, concat, firstFrame, Mp3Frame, mp3DurationMs, silence } from "../../../lib/mp3.ts";

// Audio decks for the web: a deck turned into one MP3 to listen to — each
// word's Japanese, its English meaning, a pause to say it back, optionally an
// example sentence — built in the browser from Google's speech clips (through
// /api/tts; the voice has no cross-origin access of its own) with no encoder,
// by joining MP3 frames (lib/mp3.ts).
//
// A port of mobile/lib/features/audio/audio_deck.dart: same plan, same
// assembly rules, pinned by the same cases on the same recorded clips
// (audioDeck.test.ts / audio_deck_test.dart). There is no Mongolian voice
// (the endpoint answers 400 for mn), so Mongolian meanings are shown in the
// player as text, as on mobile.

export interface AudioOptions {
  /** Speak the English meaning after the Japanese — and each sentence's translation after it. */
  english: boolean;
  /** Times each word is spoken (with its meaning) before the next. */
  repeat: number;
  /** Silence after each spoken part — time to repeat it aloud. */
  pauseMs: number;
  /** Random order instead of the deck's. */
  shuffle: boolean;
  /** After each word, an example sentence using it. */
  sentences: boolean;
}

export const DEFAULT_OPTIONS: AudioOptions = { english: true, repeat: 1, pauseMs: 1500, shuffle: false, sentences: false };

export interface AudioWord {
  term: string;
  reading?: string | null;
  meaning?: string | null;
  meaning_mn?: string | null;
}

export interface AudioExample {
  ja: string;
  en: string;
}

/** Where a word starts in the file, and what to show while it plays. */
export interface AudioCue {
  startMs: number;
  term: string;
  reading?: string | null;
  meaningMn?: string | null;
  meaning?: string | null;
  sentence?: string | null;
  sentenceEn?: string | null;
}

/** What a spoken part is, which decides what its loss costs (see assemble). */
export type PartKind = "word" | "meaning" | "sentence" | "sentenceEn";

export interface SpokenPart {
  wordIndex: number;
  text: string;
  lang: "ja" | "en";
  kind: PartKind;
}

/** The voice rejects long text; a meaning is cut at a natural break before this. */
export const MAX_CHARS = 180;

/**
 * Text as it should be spoken: whitespace collapsed, and long text cut at the
 * last sense or comma break that fits.
 */
export function speakable(text: string): string {
  const t = text.replace(/\s+/g, " ").trim();
  if (t.length <= MAX_CHARS) return t;
  for (const sep of ["; ", ", "]) {
    const cut = t.lastIndexOf(sep, MAX_CHARS);
    if (cut > 0) return t.slice(0, cut);
  }
  return t.slice(0, MAX_CHARS);
}

/**
 * What gets spoken, in order: for each word, its Japanese (the reading when
 * there is one — kana says how it's pronounced, where kanji can be misread by
 * the voice), then its English meaning, repeated `repeat` times; then, with
 * `sentences`, its example sentence once, followed by the translation when
 * English is on. `examples` runs parallel to `words`.
 */
export function planParts(words: AudioWord[], o: AudioOptions, examples: (AudioExample | null)[] = []): SpokenPart[] {
  const out: SpokenPart[] = [];
  words.forEach((w, i) => {
    for (let r = 0; r < o.repeat; r++) {
      out.push({ wordIndex: i, text: w.reading || w.term, lang: "ja", kind: "word" });
      if (o.english && w.meaning) out.push({ wordIndex: i, text: w.meaning, lang: "en", kind: "meaning" });
    }
    const ex = examples[i];
    if (o.sentences && ex) {
      out.push({ wordIndex: i, text: ex.ja, lang: "ja", kind: "sentence" });
      if (o.english && ex.en) out.push({ wordIndex: i, text: ex.en, lang: "en", kind: "sentenceEn" });
    }
  });
  return out;
}

/**
 * Joins fetched clips into one MP3 with `pauseMs` of silence after each, and
 * records where each word starts. A word whose Japanese clip is missing is
 * left out whole (its meaning alone would be confusing); a missing English
 * clip just drops the meaning; a missing sentence drops the sentence and its
 * translation, never the word.
 */
export function assemble(
  parts: SpokenPart[],
  clips: (Uint8Array | null)[],
  o: AudioOptions
): { mp3: Uint8Array<ArrayBuffer>; starts: number[]; kept: number[] } {
  let format: Mp3Frame | null = null;
  for (const c of clips) {
    format = c ? firstFrame(c) : null;
    if (format) break;
  }
  const starts: number[] = [];
  const kept: number[] = [];
  if (!format) return { mp3: new Uint8Array(0), starts, kept };
  const gap = silence(format, o.pauseMs);
  const gapMs = mp3DurationMs(gap);
  const missingJa = new Set(parts.filter((p, i) => p.kind === "word" && !clips[i]).map((p) => p.wordIndex));
  const missingSentence = new Set(parts.filter((p, i) => p.kind === "sentence" && !clips[i]).map((p) => p.wordIndex));
  const out: Uint8Array[] = [];
  let ms = 0;
  let lastWord = -1;
  parts.forEach((p, i) => {
    const clip = clips[i];
    if (missingJa.has(p.wordIndex) || !clip) return;
    if (p.kind === "sentenceEn" && missingSentence.has(p.wordIndex)) return;
    const frames = audioFrames(clip);
    const f = firstFrame(clip);
    if (frames.length === 0 || !f || !f.sameFormat(format)) return;
    if (p.wordIndex !== lastWord) {
      lastWord = p.wordIndex;
      starts.push(Math.round(ms));
      kept.push(p.wordIndex);
    }
    out.push(frames, gap);
    ms += mp3DurationMs(frames) + gapMs;
  });
  return { mp3: concat(out), starts, kept };
}

/** The word playing at `ms`. */
export function cueAt(cues: AudioCue[], ms: number): number {
  let i = 0;
  while (i + 1 < cues.length && cues[i + 1].startMs <= ms) i++;
  return i;
}

/** A built deck: the MP3 and what's in it. */
export interface AudioDeck {
  deckId: string;
  deckName: string;
  mp3: Uint8Array<ArrayBuffer>;
  durationMs: number;
  createdAt: number;
  options: AudioOptions;
  cues: AudioCue[];
  /** Words left out because their speech couldn't be fetched. */
  skipped: number;
}

export interface BuildDeps {
  /** The speech clip for `text`, or null if it can't be had. */
  clip: (text: string, lang: "ja" | "en") => Promise<Uint8Array | null>;
  /** An example sentence for a word without a saved one. */
  findExample?: (term: string) => Promise<AudioExample | null>;
  onProgress?: (done: number, total: number) => void;
  onSentenceProgress?: (done: number, total: number) => void;
  random?: () => number;
}

/** At most this many requests at once: a deck of a hundred words is a few hundred clips. */
const CONCURRENCY = 3;

async function pool(n: number, run: (i: number) => Promise<void>) {
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, n) }, async () => {
      while (next < n) await run(next++);
    })
  );
}

/**
 * Builds the deck's audio. The same text (a repeat, a shared meaning) is
 * fetched once. A word's saved sentence (0031) wins over a looked-up one.
 * Null when nothing at all could be fetched.
 */
export async function buildAudioDeck(
  deck: { id: string; name: string },
  words: (AudioWord & { example_ja?: string | null; example_en?: string | null })[],
  o: AudioOptions,
  deps: BuildDeps
): Promise<AudioDeck | null> {
  const ordered = o.shuffle ? shuffled(words, deps.random ?? Math.random) : words;
  const examples: (AudioExample | null)[] = ordered.map(() => null);
  if (o.sentences) {
    let found = 0;
    await pool(ordered.length, async (i) => {
      const w = ordered[i];
      examples[i] = w.example_ja
        ? { ja: w.example_ja, en: w.example_en ?? "" }
        : ((await deps.findExample?.(w.term).catch(() => null)) ?? null);
      deps.onSentenceProgress?.(++found, ordered.length);
    });
  }
  const parts = planParts(ordered, o, examples);
  const unique = new Map<string, Promise<Uint8Array | null>>();
  const clips: (Uint8Array | null)[] = parts.map(() => null);
  let done = 0;
  await pool(parts.length, async (i) => {
    const p = parts[i];
    const text = speakable(p.text);
    const key = `${p.lang}|${text}`;
    if (!unique.has(key)) unique.set(key, text ? deps.clip(text, p.lang).catch(() => null) : Promise.resolve(null));
    clips[i] = await unique.get(key)!;
    deps.onProgress?.(++done, parts.length);
  });
  const r = assemble(parts, clips, o);
  if (r.mp3.length === 0) return null;
  return {
    deckId: deck.id,
    deckName: deck.name,
    mp3: r.mp3,
    durationMs: Math.round(mp3DurationMs(r.mp3)),
    createdAt: Date.now(),
    options: o,
    cues: r.kept.map((w, k) => {
      const word = ordered[w];
      const ex = examples[w];
      return {
        startMs: r.starts[k],
        term: word.term,
        reading: word.reading ?? null,
        meaningMn: word.meaning_mn ?? null,
        meaning: word.meaning ?? null,
        sentence: ex?.ja ?? null,
        sentenceEn: ex?.en || null,
      };
    }),
    skipped: ordered.length - r.kept.length,
  };
}

function shuffled<T>(items: T[], rand: () => number): T[] {
  const out = items.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}
