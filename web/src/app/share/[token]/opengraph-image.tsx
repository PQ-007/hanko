import { ImageResponse } from "next/og";
import { T } from "../../decks/_lib/strings";
import { fetchSharedDeck } from "../_lib/fetchShared";

// The preview card when a share link is pasted into Messenger, Facebook,
// Discord, X… Deck name, word count and the first few words.

export const alt = "Shared deck";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const SAMPLE = 4;

/**
 * Noto Sans JP from Google Fonts, cut down to exactly the characters drawn
 * (`text=`), so it's a few KB. Satori can't read woff2; with no browser
 * user-agent Google serves TrueType. Null on any failure — the image then
 * draws in the default face rather than not at all.
 */
async function loadFont(text: string, weight: number): Promise<ArrayBuffer | null> {
  try {
    const css = await (
      await fetch(
        `https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@${weight}&text=${encodeURIComponent(text)}`
      )
    ).text();
    const src = css.match(/src: url\((.+?)\) format\('(opentype|truetype)'\)/)?.[1];
    if (!src) return null;
    const res = await fetch(src);
    return res.ok ? await res.arrayBuffer() : null;
  } catch {
    return null;
  }
}

export default async function Image({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const deck = await fetchSharedDeck(token);
  const name = deck?.name ?? T.sharedBy;
  const words = deck?.words.slice(0, SAMPLE) ?? [];
  const count = deck ? T.sharedWords(deck.words.length) : "";

  const text = [T.sharedBy, name, count, T.storyDeckHeading, ...words.map((w) => w.term + (w.reading ?? ""))].join("");
  const [bold, regular] = await Promise.all([loadFont(text, 800), loadFont(text, 400)]);
  const fonts = [
    ...(bold ? [{ name: "Noto Sans JP", data: bold, weight: 800 as const, style: "normal" as const }] : []),
    ...(regular ? [{ name: "Noto Sans JP", data: regular, weight: 400 as const, style: "normal" as const }] : []),
  ];

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          padding: "64px 72px",
          background: "linear-gradient(180deg, #e3ecf8 0%, #faf7f0 55%)",
          color: "#1f2933",
          fontFamily: "Noto Sans JP",
        }}
      >
        <div style={{ display: "flex", fontSize: 26, color: "#256abf", fontWeight: 800 }}>{T.storyDeckHeading}</div>
        <div style={{ marginTop: 40, fontSize: 24, color: "#256abf", fontWeight: 800 }}>{T.sharedBy}</div>
        <div style={{ marginTop: 8, fontSize: 68, fontWeight: 800, lineHeight: 1.1, display: "flex" }}>
          {name.length > 28 ? name.slice(0, 27) + "…" : name}
        </div>
        <div style={{ marginTop: 10, fontSize: 28, color: "#5b6470" }}>{count}</div>
        <div style={{ marginTop: "auto", display: "flex", gap: 18 }}>
          {words.map((w, i) => (
            <div
              key={i}
              style={{
                display: "flex",
                flexDirection: "column",
                padding: "18px 26px",
                borderRadius: 18,
                background: "#fff",
                border: "2px solid #e3dccb",
                borderLeft: "10px solid #256abf",
              }}
            >
              <div style={{ fontSize: 44, fontWeight: 800 }}>{w.term.length > 6 ? w.term.slice(0, 6) + "…" : w.term}</div>
              {w.reading && w.reading !== w.term ? (
                <div style={{ fontSize: 22, color: "#5b6470" }}>{w.reading.slice(0, 10)}</div>
              ) : null}
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size, fonts: fonts.length ? fonts : undefined }
  );
}
