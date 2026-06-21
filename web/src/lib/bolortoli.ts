// English -> Mongolian translation via bolor-toli's API. Runs server-side only
// so the API key is never shipped to the browser/extension.
//
// Confirmed contract:
//   GET https://bolor-toli.com/pub/translate?word=<text>&direction=1
//   header: api-key: <key>
//   response: { er: [ { w: { vars: [ { w, acro } ] } } ], ... }
//             Mongolian (Cyrillic) entries are vars where acro === "mn".
//
// Env (web/.env.local):
//   BOLOR_TOLI_API_KEY   (required)
//   BOLOR_TOLI_ENDPOINT  default https://bolor-toli.com/pub/translate
//   BOLOR_TOLI_DIRECTION default 1   (1 = English -> Mongolian)
//   BOLOR_TOLI_MAX_RESULTS default 4
//
// Note: bolor-toli rate-limits (it returns "Invalid API key" as plain text when
// you call too fast). We cache results in-memory and return "" on any failure so
// the Mongolian field just stays manually editable.

// Optional, only used when BOLOR_TOLI_API_KEY is set. The default translation
// provider is Google Translate (see translate.ts) — no key required.
export async function translateViaBolorToli(text: string): Promise<string> {
  const key = process.env.BOLOR_TOLI_API_KEY;
  const word = text.trim();
  if (!key || !word) return "";

  const endpoint =
    process.env.BOLOR_TOLI_ENDPOINT ?? "https://bolor-toli.com/pub/translate";
  const direction = process.env.BOLOR_TOLI_DIRECTION ?? "1";
  const max = Number(process.env.BOLOR_TOLI_MAX_RESULTS ?? "4");

  const url = new URL(endpoint);
  url.searchParams.set("word", word);
  url.searchParams.set("direction", direction);

  const res = await fetch(url, {
    headers: { "api-key": key, Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`bolor-toli ${res.status}`);

  // Rate-limited / error responses come back as plain text, not JSON.
  const body = await res.text();
  let data: BolorToliResponse;
  try {
    data = JSON.parse(body);
  } catch {
    throw new Error(`bolor-toli non-JSON response: ${body.slice(0, 60)}`);
  }

  return extractMongolian(data, max);
}

interface BolorToliVar {
  w?: string;
  acro?: string;
}
interface BolorToliEntry {
  w?: { vars?: BolorToliVar[] };
}
interface BolorToliResponse {
  er?: BolorToliEntry[];
}

// Collect the Cyrillic-Mongolian (acro === "mn") translations from the exact
// results, de-duplicated, up to `max`, joined with ", ".
function extractMongolian(data: BolorToliResponse, max: number): string {
  const seen = new Set<string>();
  for (const entry of data.er ?? []) {
    for (const v of entry.w?.vars ?? []) {
      if (v.acro === "mn" && v.w) seen.add(v.w);
    }
    if (seen.size >= max) break;
  }
  return [...seen].slice(0, max).join(", ");
}
