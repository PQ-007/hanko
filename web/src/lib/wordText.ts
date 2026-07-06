import type { Word } from "@/lib/types";

// Pure text helpers shared between the Anki export routes and the practice
// review UI. Kept dependency-free (no server-only imports) so client
// components can use them without pulling in @/lib/supabase/server.

export function sanitizeFilename(name: string): string {
  return name.replace(/[^a-z0-9-_]+/gi, "_").slice(0, 60) || "deck";
}

export function sanitizeTag(name: string): string {
  return name.replace(/\s+/g, "_").replace(/[^\w-]/g, "");
}

// Front field text: "term (reading)" when the reading adds information.
export function frontText(word: Word): string {
  return word.reading && word.reading !== word.term
    ? `${word.term} (${word.reading})`
    : word.term;
}

// Back field: English meaning plus the Mongolian translation on its own line
// (newline-separated; callers turn "\n" into <br> as needed).
export function backText(word: Word): string {
  return [word.meaning ?? "", word.meaning_mn ?? ""]
    .map((s) => s.trim())
    .filter(Boolean)
    .join("\n");
}
