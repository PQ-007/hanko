// Handwritten kanji → candidate characters, for the add-word dialog's pad.
//
// Recognition is Google Input Tools' keyless handwriting endpoint — the same
// family as the keyless Translate and TTS endpoints the app already leans on.
// It answers CORS from any origin, so the browser calls it directly: no route
// of ours in between, and so no second open proxy to rate-limit (compare
// /api/lookup). Mobile doesn't use this; it has ML Kit's on-device digital ink.
//
// The stroke grader in writing/_lib/strokes.ts is not a substitute: it checks
// ink against one known kanji, it can't say which of ~6,000 was drawn.

/** A stroke as the pad records it: points in pad pixels. */
type Stroke = [number, number][];

const ENDPOINT = "https://inputtools.google.com/request?ime=handwriting&app=mobilesearch&cs=1&oe=UTF-8";

/**
 * The endpoint's ink format: per stroke, [xs, ys, times]. Times are optional
 * (an empty list is accepted) and the pad doesn't record them; coordinates are
 * rounded because sub-pixel precision only makes the request bigger.
 */
export function toGoogleInk(ink: Stroke[]): [number[], number[], number[]][] {
  return ink
    .filter((s) => s.length > 0)
    .map((s) => [s.map((p) => Math.round(p[0])), s.map((p) => Math.round(p[1])), []]);
}

/**
 * ["SUCCESS", [[id, ["日", "曰", …], …]]] → the candidates, in order, without
 * repeats or blanks. Anything else — an error status, a changed shape — is no
 * candidates rather than a throw: the pad is a convenience next to a text box.
 */
export function parseCandidates(body: unknown, max = 10): string[] {
  if (!Array.isArray(body) || body[0] !== "SUCCESS") return [];
  const list = (body[1] as unknown[] | undefined)?.[0];
  const cands = Array.isArray(list) ? list[1] : null;
  if (!Array.isArray(cands)) return [];
  const out: string[] = [];
  for (const c of cands) {
    if (typeof c !== "string") continue;
    const t = c.trim();
    if (t && !out.includes(t)) out.push(t);
    if (out.length >= max) break;
  }
  return out;
}

/**
 * Asks for the characters `ink` most likely is. `preContext` is the text
 * already in front of the caret — the recogniser uses it, so the second kanji
 * of a word comes back ranked by what makes a word with the first.
 */
export async function recognizeKanji(
  ink: Stroke[],
  area: { width: number; height: number },
  preContext = "",
  signal?: AbortSignal
): Promise<string[]> {
  const strokes = toGoogleInk(ink);
  if (strokes.length === 0) return [];
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    signal,
    body: JSON.stringify({
      options: "enable_pre_space",
      requests: [
        {
          writing_guide: { writing_area_width: Math.round(area.width), writing_area_height: Math.round(area.height) },
          pre_context: preContext,
          max_num_results: 10,
          max_completions: 0,
          language: "ja",
          ink: strokes,
        },
      ],
    }),
  });
  if (!res.ok) throw new Error(`Handwriting ${res.status}`);
  return parseCandidates(await res.json());
}

/** Puts `s` over the selection [start, end) of `text`; the caret lands after it. */
export function insertAt(text: string, start: number, end: number, s: string): { text: string; caret: number } {
  const a = Math.max(0, Math.min(start, text.length));
  const b = Math.max(a, Math.min(end, text.length));
  return { text: text.slice(0, a) + s + text.slice(b), caret: a + s.length };
}
