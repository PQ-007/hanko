// A full-screen story image (Instagram / Facebook stories) drawn on a canvas
// in the browser — no server, no package. Sized to the phone it's made on
// (storySize), so it fills that screen edge to edge instead of the old fixed
// 16:9 frame, which left bars on today's 19.5:9–20:9 phones. Two uses: "today's words" from the
// stats page, and a shared deck's invitation from the deck share dialog.

export interface StoryWord {
  term: string;
  reading: string | null;
  meaning: string | null;
}

export interface StoryCard {
  /** Small line over the heading, e.g. the date or "shared deck". */
  kicker: string;
  heading: string;
  stats: string;
  /** Optional line under the stats, e.g. a streak. */
  badge?: string;
  words: StoryWord[];
  /** How many words there are in all; the rest show as "+N" after the list. */
  total?: number;
  moreLabel?: (n: number) => string;
  /** Where to go, printed at the bottom (a link sticker can't be drawn). */
  footer: string;
}

export const STORY_W = 1080;
/** Most words a card ever lists (fewer when the screen is short). */
export const STORY_MAX_WORDS = 10;

/**
 * The image size for this device: 1080 wide, as tall as the screen's own
 * shape — a Galaxy A32 (1080×2400) gets 1080×2400. Desktops and anything
 * landscape get a typical modern phone, 1080×2340 (19.5:9). Clamped between
 * 16:9 and 22:9 so an odd window can't produce a strip.
 */
export function storySize(): { width: number; height: number } {
  let ratio = 2340 / 1080;
  if (typeof window !== "undefined" && window.screen) {
    const { width, height } = window.screen;
    if (width > 0 && height > width) ratio = height / width;
  }
  ratio = Math.min(22 / 9, Math.max(16 / 9, ratio));
  return { width: STORY_W, height: Math.round(STORY_W * ratio) };
}

const PAPER = "#faf7f0";
const PAPER_DIM = "#f1ebdd";
const INK = "#1f2933";
const INK_SOFT = "#5b6470";
const SEAL = "#256abf";
const SEAL_DARK = "#184f95";
const LINE = "#e3dccb";

// Japanese first: the canvas has no page fonts of its own, and a Latin-only
// face would draw tofu for every kanji.
const FONT =
  '"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", "Noto Sans CJK JP", "Yu Gothic", "Meiryo", system-ui, sans-serif';

function font(weight: number, size: number) {
  return `${weight} ${size}px ${FONT}`;
}

/** The largest size ≤ max at which text fits in width (never below min). */
function fit(ctx: CanvasRenderingContext2D, text: string, weight: number, max: number, min: number, width: number) {
  let size = max;
  ctx.font = font(weight, size);
  while (size > min && ctx.measureText(text).width > width) {
    size -= 2;
    ctx.font = font(weight, size);
  }
  return size;
}

/** Cut with an ellipsis once text no longer fits at the current font. */
function clip(ctx: CanvasRenderingContext2D, text: string, width: number) {
  if (ctx.measureText(text).width <= width) return text;
  let t = text;
  while (t.length > 1 && ctx.measureText(t + "…").width > width) t = t.slice(0, -1);
  return t + "…";
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** The hanko seal: a rounded seal-blue square with 判 — the app's mark. */
function seal(ctx: CanvasRenderingContext2D, x: number, y: number, size: number) {
  ctx.save();
  ctx.translate(x + size / 2, y + size / 2);
  ctx.rotate(-0.06);
  ctx.fillStyle = SEAL;
  roundRect(ctx, -size / 2, -size / 2, size, size, size * 0.18);
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.85)";
  ctx.lineWidth = size * 0.04;
  roundRect(ctx, -size / 2 + size * 0.09, -size / 2 + size * 0.09, size * 0.82, size * 0.82, size * 0.12);
  ctx.stroke();
  ctx.fillStyle = "#fff";
  ctx.font = font(800, size * 0.55);
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("判", 0, size * 0.03);
  ctx.restore();
}

export function drawStoryCard(ctx: CanvasRenderingContext2D, card: StoryCard) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 88;
  ctx.textBaseline = "alphabetic";
  ctx.textAlign = "left";

  // Paper, with a soft seal-blue wash at the top.
  ctx.fillStyle = PAPER;
  ctx.fillRect(0, 0, W, H);
  const wash = ctx.createLinearGradient(0, 0, 0, 760);
  wash.addColorStop(0, "rgba(37,106,191,0.16)");
  wash.addColorStop(1, "rgba(37,106,191,0)");
  ctx.fillStyle = wash;
  ctx.fillRect(0, 0, W, 760);
  // A large faint 判 behind everything.
  ctx.fillStyle = "rgba(37,106,191,0.05)";
  ctx.font = font(900, 900);
  ctx.textAlign = "right";
  ctx.fillText("判", W + 120, 900);
  ctx.textAlign = "left";

  // Brand row.
  seal(ctx, M, 150, 96);
  ctx.fillStyle = INK;
  ctx.font = font(800, 52);
  ctx.fillText("Hanko", M + 124, 212);

  // Kicker, heading, stats.
  let y = 380;
  ctx.fillStyle = SEAL;
  ctx.font = font(700, 34);
  ctx.fillText(clip(ctx, card.kicker.toUpperCase(), W - 2 * M), M, y);
  y += 96;
  const hs = fit(ctx, card.heading, 900, 92, 56, W - 2 * M);
  ctx.fillStyle = INK;
  ctx.font = font(900, hs);
  ctx.fillText(clip(ctx, card.heading, W - 2 * M), M, y);
  y += 72;
  ctx.fillStyle = INK_SOFT;
  ctx.font = font(600, 38);
  ctx.fillText(clip(ctx, card.stats, W - 2 * M), M, y);
  if (card.badge) {
    y += 64;
    ctx.font = font(700, 36);
    const bw = Math.min(W - 2 * M, ctx.measureText(card.badge).width + 56);
    ctx.fillStyle = "rgba(245,158,11,0.16)";
    roundRect(ctx, M, y - 44, bw, 64, 32);
    ctx.fill();
    ctx.fillStyle = "#b45309";
    ctx.fillText(clip(ctx, card.badge, bw - 56), M + 28, y);
  }

  // The words, one card each.
  // The words, one card each — as many as the screen fits, rows growing to
  // fill a tall screen rather than leaving its bottom half empty.
  const listTop = y + 70;
  const footerTop = H - 230;
  const gap = 22;
  const MIN_ROW = 128, MAX_ROW = 180, MORE_H = 80;
  const space = footerTop - listTop - MORE_H;
  const fits = Math.max(1, Math.floor((space + gap) / (MIN_ROW + gap)));
  const words = card.words.slice(0, Math.min(fits, STORY_MAX_WORDS));
  const more = Math.max(0, (card.total ?? card.words.length) - words.length);
  const rowH = Math.min(MAX_ROW, (space + (more ? 0 : MORE_H)) / Math.max(words.length, 1) - gap);
  // A short list sits in the free space rather than hugging the heading.
  const used = words.length * (rowH + gap) + (more ? MORE_H : 0);
  let ry = listTop + Math.max(0, (footerTop - listTop - used) / 3);
  for (const w of words) {
    ctx.fillStyle = "#ffffff";
    ctx.shadowColor = "rgba(31,41,51,0.08)";
    ctx.shadowBlur = 24;
    ctx.shadowOffsetY = 6;
    roundRect(ctx, M, ry, W - 2 * M, rowH, 28);
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.strokeStyle = LINE;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = SEAL;
    roundRect(ctx, M, ry, 12, rowH, 6);
    ctx.fill();

    const pad = 44;
    const termW = (W - 2 * M) * 0.46;
    const ts = fit(ctx, w.term, 800, Math.min(64, rowH * 0.46), 34, termW);
    const reading = w.reading && w.reading !== w.term ? w.reading : "";
    const mid = ry + rowH / 2;
    ctx.fillStyle = INK;
    ctx.font = font(800, ts);
    ctx.fillText(clip(ctx, w.term, termW), M + pad, reading ? mid + ts * 0.1 : mid + ts * 0.35);
    if (reading) {
      ctx.fillStyle = INK_SOFT;
      ctx.font = font(500, Math.min(30, rowH * 0.2));
      ctx.fillText(clip(ctx, reading, termW), M + pad, mid + ts * 0.1 + Math.min(42, rowH * 0.3));
    }
    if (w.meaning) {
      const mx = M + pad + termW + 24;
      const mw = W - M - pad - mx;
      ctx.fillStyle = INK;
      ctx.font = font(600, Math.min(36, rowH * 0.25));
      ctx.fillText(clip(ctx, w.meaning, mw), mx, mid + 12);
    }
    ry += rowH + gap;
  }
  if (more > 0) {
    ctx.fillStyle = INK_SOFT;
    ctx.font = font(700, 38);
    ctx.textAlign = "center";
    ctx.fillText((card.moreLabel ?? ((n: number) => `+${n}`))(more), W / 2, ry + 44);
    ctx.textAlign = "left";
  }

  // Footer: where to go.
  ctx.fillStyle = PAPER_DIM;
  ctx.fillRect(0, footerTop + 40, W, H - footerTop - 40);
  ctx.fillStyle = SEAL_DARK;
  ctx.textAlign = "center";
  const fs = fit(ctx, card.footer, 700, 40, 24, W - 2 * M);
  ctx.font = font(700, fs);
  ctx.fillText(clip(ctx, card.footer, W - 2 * M), W / 2, footerTop + 140);
  ctx.textAlign = "left";
}

/** The card as a PNG. Waits for fonts so the first render isn't in a fallback face. */
export async function renderStoryCard(
  card: StoryCard,
  size: { width: number; height: number } = storySize()
): Promise<Blob> {
  try {
    await document.fonts?.ready;
  } catch {
    // Font loading API missing — draw with whatever is there.
  }
  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("canvas unavailable");
  drawStoryCard(ctx, card);
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("toBlob failed"))), "image/png")
  );
}
