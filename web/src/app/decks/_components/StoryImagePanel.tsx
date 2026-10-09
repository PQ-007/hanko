"use client";

import { useEffect, useMemo, useState } from "react";
import { Noto_Sans } from "next/font/google";
import { Download, RefreshCw, Share2 } from "@/ui/icons";
import { T } from "../_lib/strings";
import {
  buildStoryQuiz,
  renderStoryCard,
  storySize,
  STORY_LAYOUTS,
  type StoryCard,
  type StoryLang,
  type StoryLayout,
  type StoryStyle,
} from "../_lib/storyCard";

// The story image's text face: full Mongolian Cyrillic (Ө ө Ү ү are in the
// cyrillic-ext subset), variable weight, self-hosted by next/font.
const storyFont = Noto_Sans({ subsets: ["latin", "cyrillic", "cyrillic-ext"], display: "swap" });

/**
 * A story card's preview with Share (the phone's share sheet — Instagram,
 * Facebook, Messenger… — where the browser can share files) and Download
 * (everywhere else, e.g. desktop).
 */
const OPTS_KEY = "hanko.story.opts";

type Opts = { style: StoryStyle; lang: StoryLang; layout: StoryLayout };

function readOpts(): Opts {
  try {
    const o = JSON.parse(window.localStorage.getItem(OPTS_KEY) ?? "{}");
    return {
      style: ["seal", "dark", "paper"].includes(o.style) ? o.style : "seal",
      lang: ["mn", "en", "both"].includes(o.lang) ? o.lang : "mn",
      layout: STORY_LAYOUTS.includes(o.layout) ? o.layout : "grid",
    };
  } catch {
    return { style: "seal", lang: "mn", layout: "grid" };
  }
}

const LAYOUT_LABEL: Record<StoryLayout, string> = {
  grid: T.storyLayoutGrid,
  list: T.storyLayoutList,
  spotlight: T.storyLayoutSpotlight,
  quiz: T.storyLayoutQuiz,
};

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
  // Which word Spotlight/Quiz show (and the quiz's answer slot): "another word".
  const [seed, setSeed] = useState(0);
  const quizOk = useMemo(() => buildStoryQuiz(card.words, opts.lang, 0) !== null, [card.words, opts.lang]);
  const layout: StoryLayout = opts.layout === "quiz" && !quizOk ? "grid" : opts.layout;
  const full: StoryCard = {
    ...card,
    style: opts.style,
    lang: opts.lang,
    layout,
    seed,
    quizPrompt: T.storyQuizPrompt,
    quizAnswer: T.storyQuizAnswer,
  };
  // Re-render when anything drawn changes. moreLabel is a function, which the
  // JSON round-trip drops — it used to, and "+20 үг" came out as a bare "+20" —
  // so it's passed back in alongside.
  const key = JSON.stringify(full);
  const moreLabel = card.moreLabel;

  useEffect(() => {
    let url: string | null = null;
    let cancelled = false;
    renderStoryCard({ ...JSON.parse(key), moreLabel }, size, storyFont.style.fontFamily)
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
  }, [key, size, moreLabel]);

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
        <div className="flex flex-col gap-1.5">
          <span className="text-xs font-medium text-ink-soft">{T.storyLayoutLabel}</span>
          <div role="radiogroup" aria-label={T.storyLayoutLabel} className="grid grid-cols-4 gap-1.5">
            {STORY_LAYOUTS.map((l) => {
              const disabled = l === "quiz" && !quizOk;
              return (
                <button
                  key={l}
                  role="radio"
                  aria-checked={layout === l}
                  disabled={disabled}
                  title={disabled ? T.storyQuizNeedsWords : LAYOUT_LABEL[l]}
                  onClick={() => pick({ layout: l })}
                  className={`flex flex-col items-center gap-1 rounded-control border px-1 py-1.5 text-[11px] font-medium transition disabled:cursor-not-allowed disabled:opacity-40 ${
                    layout === l ? "border-seal bg-seal-tint text-ink" : "border-line text-ink-soft hover:border-ink-mute"
                  }`}
                >
                  <LayoutGlyph layout={l} />
                  {LAYOUT_LABEL[l]}
                </button>
              );
            })}
          </div>
          {(layout === "spotlight" || layout === "quiz") && card.words.length > 1 && (
            <button
              onClick={() => setSeed((n) => n + 1)}
              className="flex items-center justify-center gap-1.5 self-center rounded-control px-2.5 py-1 text-xs font-medium text-seal hover:bg-paper-dim"
            >
              <RefreshCw size={13} /> {T.storyNextWord}
            </button>
          )}
        </div>
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

/** A tiny drawing of each layout, for the picker. */
function LayoutGlyph({ layout }: { layout: StoryLayout }) {
  const box = "fill-current opacity-60";
  return (
    <svg viewBox="0 0 18 28" width="16" height="24" aria-hidden className="text-current">
      <rect x="0.5" y="0.5" width="17" height="27" rx="3" className="fill-none stroke-current" strokeWidth="1" />
      {layout === "grid" && [6, 13, 20].flatMap((y) => [3, 9.5].map((x) => <rect key={`${x}${y}`} x={x} y={y} width="5.5" height="5" rx="1" className={box} />))}
      {layout === "list" && [6, 11, 16, 21].map((y) => <rect key={y} x="3" y={y} width="12" height="3.5" rx="1" className={box} />)}
      {layout === "spotlight" && (
        <>
          <rect x="3" y="8" width="12" height="13" rx="1.5" className={box} />
        </>
      )}
      {layout === "quiz" && (
        <>
          <rect x="3" y="4" width="12" height="7" rx="1.5" className={box} />
          {[13, 16.5, 20, 23.5].map((y) => <rect key={y} x="3" y={y} width="12" height="2.3" rx="1" className={box} />)}
        </>
      )}
    </svg>
  );
}
