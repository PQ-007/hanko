// Which add-word fields a dictionary match may fill — the add dialog's one
// rule that is easy to get subtly wrong.
//
// The dialog looks the term up as it changes (typed or drawn), so a match
// arrives many times per word. It may write into a field that is empty or
// that it filled itself last time; once the user has typed into a field, that
// field is theirs and later matches leave it alone. Without the second half,
// drawing 生 then 活 would leave 生's reading under 生活.

export interface WordFields {
  term: string;
  reading: string;
  meaning: string;
  meaningMn: string;
}

/** Fields whose current value came from a lookup or a translation, not the user. */
export type AutoKey = "reading" | "meaning" | "meaningMn";

export interface Match {
  word: string;
  reading: string;
  meaning: string;
}

/**
 * Fills the fields still open to the machine from `m`. The term is never
 * touched — rewriting what is under the user's caret mid-word is worse than a
 * conjugated form, which accepting a match (Enter, Tab) still fixes.
 *
 * When the English changes, a machine-filled Mongolian meaning is cleared
 * rather than left describing the old word; the caller re-translates.
 */
export function autofill(
  f: WordFields,
  auto: ReadonlySet<AutoKey>,
  m: Match
): { fields: WordFields; auto: Set<AutoKey>; meaningChanged: boolean } {
  const next = new Set(auto);
  const open = (k: AutoKey) => f[k].trim() === "" || auto.has(k);
  const fields = { ...f };
  if (open("reading")) {
    fields.reading = m.reading;
    next.add("reading");
  }
  if (open("meaning")) {
    fields.meaning = m.meaning;
    next.add("meaning");
  }
  const meaningChanged = fields.meaning !== f.meaning;
  if (meaningChanged && open("meaningMn")) {
    fields.meaningMn = "";
    next.add("meaningMn");
  }
  return { fields, auto: next, meaningChanged };
}

/** The match a field set came from, if any — the one the list shows as picked. */
export function pickedMatch<T extends Match>(f: WordFields, matches: readonly T[]): T | null {
  const term = f.term.trim();
  return matches.find((m) => m.word === term && m.reading === f.reading.trim()) ?? null;
}
