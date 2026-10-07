"use client";

import { useEffect, useState } from "react";
import { Noto_Sans } from "next/font/google";
import { Download, Share2 } from "@/ui/icons";
import { T } from "../_lib/strings";
import { renderStoryCard, storySize, type StoryCard, type StoryLang, type StoryStyle } from "../_lib/storyCard";

// The story image's text face: full Mongolian Cyrillic (Ө ө Ү ү are in the
// cyrillic-ext subset), variable weight, self-hosted by next/font.
const storyFont = Noto_Sans({ subsets: ["latin", "cyrillic", "cyrillic-ext"], display: "swap" });

/**
 * A story card's preview with Share (the phone's share sheet — Instagram,
 * Facebook, Messenger… — where the browser can share files) and Download
 * (everywhere else, e.g. desktop).
 */
const OPTS_KEY = "hanko.story.opts";

function readOpts(): { style: StoryStyle; lang: StoryLang } {
  try {
    const o = JSON.parse(window.localStorage.getItem(OPTS_KEY) ?? "{}");
    return {
      style: ["seal", "dark", "paper"].includes(o.style) ? o.style : "seal",
      lang: ["mn", "en", "both"].includes(o.lang) ? o.lang : "mn",
    };
  } catch {
    return { style: "seal", lang: "mn" };
  }
}

export default function StoryImagePanel({ card, fileName }: { card: StoryCard; fileName: string }) {
  const [image, setImage] = useState<{ blob: Blob; url: string } | null>(null);
  const [failed, setFailed] = useState(false);
  // The device's own story shape, read once (window.screen isn't there on the server).
  const [size] = useState(storySize);
  // Style and meaning language, remembered per device.
  const [opts, setOpts] = useState(readOpts);
  function pick(next: Partial<typeof opts>) {
    const o = { ...opts, ...next };
    setOpts(o);
    try {
      window.localStorage.setItem(OPTS_KEY, JSON.stringify(o));
    } catch {
      // Not remembered — a small loss.
    }
  }
  const key = JSON.stringify({ ...card, style: opts.style, lang: opts.lang });

  useEffect(() => {
    let url: string | null = null;
    let cancelled = false;
    renderStoryCard(JSON.parse(key), size, storyFont.style.fontFamily)
      .then((blob) => {
        if (cancelled) return;
        url = URL.createObjectURL(blob);
        setImage({ blob, url });
      })
      .catch(() => !cancelled && setFailed(true));
    return () => {
      cancelled = true;
      if (url) URL.revokeObjectURL(url);
    };
  }, [key, size]);

  const file = image ? new File([image.blob], `${fileName}.png`, { type: "image/png" }) : null;
  const canShareFile =
    !!file && typeof navigator !== "undefined" && !!navigator.canShare?.({ files: [file] });

  function download() {
    if (!image) return;
    const a = document.createElement("a");
    a.href = image.url;
    a.download = `${fileName}.png`;
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  async function share() {
    if (!file) return;
    try {
      await navigator.share({ files: [file] });
    } catch {
      // Dismissed, or the target refused the file — nothing to report.
    }
  }

  return (
    <div className="flex flex-col items-center gap-3">
      <div
        style={{ aspectRatio: `${size.width} / ${size.height}` }}
        className="w-full max-w-[200px] overflow-hidden rounded-control border border-line bg-paper-dim shadow-sm"
      >
        {image ? (
          // eslint-disable-next-line @next/next/no-img-element -- a local blob URL
          <img src={image.url} alt={card.heading} className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full items-center justify-center text-xs text-ink-mute">
            {failed ? T.shareFailed : "…"}
          </div>
        )}
      </div>
      <div className="flex w-full flex-col gap-2">
        <div className="flex items-center justify-between gap-2">
          <span className="text-xs font-medium text-ink-soft">{T.storyStyleLabel}</span>
          <div role="radiogroup" aria-label={T.storyStyleLabel} className="flex gap-1.5">
            {(
              [
                ["seal", T.storyStyleSeal, "bg-[linear-gradient(180deg,#2c72cc,#0f3672)]"],
                ["dark", T.storyStyleDark, "bg-[#14181e]"],
                ["paper", T.storyStylePaper, "bg-[radial-gradient(circle_at_50%_50%,#c8442f_0_28%,#f8f2e6_32%)]"],
              ] as const
            ).map(([v, label, sw]) => (
              <button
                key={v}
                role="radio"
                aria-checked={opts.style === v}
                title={label}
                onClick={() => pick({ style: v })}
                className={`flex items-center gap-1.5 rounded-full border px-2 py-1 text-xs font-medium transition ${
                  opts.style === v ? "border-seal text-ink" : "border-line text-ink-soft hover:border-ink-mute"
                }`}
              >
                <span className={`h-3.5 w-3.5 rounded-full border border-black/10 ${sw}`} />
                {label}
              </button>
            ))}
          </div>
        </div>
        <div className="flex items-center justify-between gap-2">
          <span className="text-xs font-medium text-ink-soft">{T.storyLangLabel}</span>
          <div role="radiogroup" aria-label={T.storyLangLabel} className="inline-flex rounded-control bg-paper-dim p-0.5 text-xs">
            {(
              [
                ["mn", T.storyLangMn],
                ["en", T.storyLangEn],
                ["both", T.storyLangBoth],
              ] as const
            ).map(([v, label]) => (
              <button
                key={v}
                role="radio"
                aria-checked={opts.lang === v}
                onClick={() => pick({ lang: v })}
                className={`rounded-control px-2.5 py-1 font-medium transition ${
                  opts.lang === v ? "bg-surface text-ink shadow-sm" : "text-ink-soft hover:text-ink"
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      </div>
      <p className="text-center text-xs text-ink-mute">{T.shareImageHint(size.width, size.height)}</p>
      <div className="flex w-full gap-2">
        {canShareFile && (
          <button onClick={share} className="hk-btn hk-btn-primary flex-1 px-4 py-2.5 text-sm">
            <Share2 size={15} /> {T.shareImageShare}
          </button>
        )}
        <button
          onClick={download}
          disabled={!image}
          className={`hk-btn flex-1 px-4 py-2.5 text-sm disabled:opacity-50 ${canShareFile ? "hk-btn-quiet" : "hk-btn-primary"}`}
        >
          <Download size={15} /> {T.shareImageDownload}
        </button>
      </div>
    </div>
  );
}
