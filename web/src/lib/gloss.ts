// Short, duplicate-free glosses. meaning and meaning_mn are shown on cards and
// fed to audio/video reviews, so they hold the point of the word, not every
// Jisho sense. Mirrored by compactGloss in mobile/lib/core/dictionary.dart and
// in the extension's background.js.

// Most items a gloss keeps, and the length past which no further item is
// added (the first is always kept).
export const MAX_ITEMS = 3;
export const MAX_CHARS = 40;

// Drops bracketed notes: Jisho's "(e.g. a salary)", "(a task)" and the like.
// Translated, they only make the gloss longer.
export function stripNotes(text: string): string {
  return text
    .replace(/\([^()]*\)|（[^（）]*）|\[[^\]]*\]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

// Dictionary meanings are synonym lists split by "," and ";" ("careful,
// cautious, prudent; discreet"), and Google maps many of them to the same
// Mongolian word: "болгоомжтой, болгоомжтой, болгоомжтой; болгоомжтой". Keep
// each item once, notes stripped, at most MAX_ITEMS and about MAX_CHARS long.
// Used for both the English meaning (jisho.ts) and its Mongolian translation.
export function compactGloss(text: string): string {
  const seen = new Set<string>();
  const items: string[] = [];
  let length = 0;
  for (const raw of text.split(/[,;、，；\n]/)) {
    const item = stripNotes(raw).replace(/^[\s.:-]+|[\s.:-]+$/g, "");
    const key = item.toLowerCase();
    if (!item || seen.has(key)) continue;
    seen.add(key);
    if (items.length && length + 2 + item.length > MAX_CHARS) break;
    items.push(item);
    length += (items.length > 1 ? 2 : 0) + item.length;
    if (items.length === MAX_ITEMS) break;
  }
  return items.join(", ");
}
