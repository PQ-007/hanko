// Text-to-speech for word pronunciation. Pluggable provider:
//   - "google-translate" (default): unofficial Google Translate TTS endpoint.
//     No API key, good enough for single words/short phrases. Same spirit as the
//     unofficial Jisho dictionary the project already relies on.
//   - "google-cloud": official Google Cloud Text-to-Speech (needs an API key).
//
// Returns MP3 bytes. Throws on failure so the route can report it.

const PROVIDER = process.env.TTS_PROVIDER ?? "google-translate";

export async function synthesizeMp3(text: string, lang = "ja"): Promise<Uint8Array> {
  if (PROVIDER === "google-cloud") return googleCloud(text, lang);
  return googleTranslate(text, lang);
}

async function googleTranslate(text: string, lang: string): Promise<Uint8Array> {
  const url = `https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=${encodeURIComponent(
    lang
  )}&q=${encodeURIComponent(text)}`;
  const res = await fetch(url, {
    headers: {
      // The endpoint rejects requests without a browser-like User-Agent.
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    },
  });
  if (!res.ok) throw new Error(`TTS failed (${res.status})`);
  return new Uint8Array(await res.arrayBuffer());
}

async function googleCloud(text: string, lang: string): Promise<Uint8Array> {
  const key = process.env.GOOGLE_CLOUD_TTS_API_KEY;
  if (!key) throw new Error("GOOGLE_CLOUD_TTS_API_KEY is not set");
  const res = await fetch(
    `https://texttospeech.googleapis.com/v1/text:synthesize?key=${key}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        input: { text },
        voice: { languageCode: lang === "ja" ? "ja-JP" : lang },
        audioConfig: { audioEncoding: "MP3" },
      }),
    }
  );
  if (!res.ok) throw new Error(`TTS failed (${res.status})`);
  const data = await res.json();
  return Uint8Array.from(Buffer.from(data.audioContent, "base64"));
}
