// Where to send someone after sign-in (`?next=`), only ever a path on this
// site. The callback builds `${origin}${next}`, so an unchecked value like
// "@evil.example" or "//evil.example" would turn a real Google sign-in into a
// redirect to another site — a ready-made phishing link.
export const DEFAULT_NEXT = "/decks";

export function safeNext(raw: string | null | undefined, fallback = DEFAULT_NEXT): string {
  if (!raw) return fallback;
  // One leading slash, then not another slash or a backslash (browsers treat
  // "/\\host" like "//host"); no control characters anywhere.
  if (!/^\/(?![/\\])/.test(raw) || /[\u0000-\u001f\\]/.test(raw)) return fallback;
  return raw;
}
