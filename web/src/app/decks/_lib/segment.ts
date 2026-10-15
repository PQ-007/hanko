// Word suggestions from OCR'd Japanese text, with no dictionary in the browser
// and no tokenizer anywhere. A port of mobile/lib/features/capture/segment.dart,
// pinned by the same cases (segment.test.ts / segment_test.dart) — see there
// for why script boundaries rather than kuromoji/MeCab.
//
// - a kanji run plus the hiragana right after it (食べ + ました) is a verb or
//   adjective with its ending; Jisho resolves it (食べました → 食べる);
// - a kanji run followed by a particle (日本語 + を) is a noun on its own;
// - a katakana run of two or more characters is a loanword.
// Hiragana-only words are never suggested; selecting text covers them.

type Script = "kanji" | "hiragana" | "katakana" | "other";

function scriptOf(c: number): Script {
  // 々 (iteration mark) and 〆 behave as kanji inside a word.
  if ((c >= 0x4e00 && c <= 0x9fff) || (c >= 0x3400 && c <= 0x4dbf) || c === 0x3005 || c === 0x3006) return "kanji";
  if (c >= 0x3041 && c <= 0x309f) return "hiragana";
  // ー (long vowel mark) and the half-width block count as katakana.
  if ((c >= 0x30a0 && c <= 0x30ff) || (c >= 0xff66 && c <= 0xff9f)) return "katakana";
  return "other";
}

/**
 * Hiragana that, at the start of the run after a kanji word, mark it as a noun
 * followed by a particle rather than a word with okurigana. か and と are left
 * out: 書かない and 落とす are far more common than a noun followed by them.
 */
const PARTICLES = new Set(["は", "が", "を", "に", "で", "も", "の", "へ", "や"]);

/** The longest ending kept after a kanji run. */
const MAX_ENDING = 6;

function runs(line: string): { script: Script; text: string }[] {
  const out: { script: Script; text: string }[] = [];
  for (const ch of line) {
    const s = scriptOf(ch.codePointAt(0)!);
    const last = out[out.length - 1];
    if (last && last.script === s) last.text += ch;
    else out.push({ script: s, text: ch });
  }
  return out;
}

/** The okurigana part of a hiragana run: up to the first particle after the first character, capped. */
function ending(run: string): string {
  const chars = Array.from(run);
  let end = chars.length;
  for (let i = 1; i < chars.length; i++) {
    if (PARTICLES.has(chars[i])) {
      end = i;
      break;
    }
  }
  return chars.slice(0, Math.min(end, MAX_ENDING)).join("");
}

/** Candidate words in reading order, each once — surface forms; dictionary forms come from the lookup. */
export function suggestWords(lines: Iterable<string>): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  const add = (w: string) => {
    if (w && !seen.has(w)) {
      seen.add(w);
      out.push(w);
    }
  };
  for (const line of lines) {
    const rs = runs(line);
    rs.forEach((r, i) => {
      if (r.script === "katakana") {
        // A lone ー or a single katakana is noise (or a furigana scrap).
        if (Array.from(r.text.replaceAll("ー", "")).length >= 2) add(r.text);
      } else if (r.script === "kanji") {
        const next = rs[i + 1];
        if (!next || next.script !== "hiragana" || PARTICLES.has(Array.from(next.text)[0])) add(r.text);
        else add(r.text + ending(next.text));
      }
    });
  }
  return out;
}

/**
 * Whether a Jisho result is plausibly the word that was asked about, rather
 * than its fuzzy best guess at something else: a kanji word's dictionary form
 * starts with the same kanji (食べました → 食べる); a katakana word is its
 * own dictionary form.
 */
export function lookupMatches(candidate: string, dictionaryForm: string): boolean {
  if (!dictionaryForm || !candidate) return false;
  const first = candidate.codePointAt(0)!;
  if (scriptOf(first) === "katakana") return dictionaryForm === candidate;
  return dictionaryForm.codePointAt(0) === first;
}
