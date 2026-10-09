// A full-screen, unbranded story image (Instagram / Facebook stories) drawn on
// a canvas in the browser — no server, no package. Sized to the phone it's made
// on (storySize), so it fills that screen edge to edge. Two uses: "today's
// words" from the stats page, and a shared deck's invitation from the deck
// share dialog. mobile/lib/features/share/story_card.dart is a port.
//
// Four layouts (StoryLayout):
//   grid       header (kicker, headline, up to three big numbers), then a
//              two-column grid of word tiles and a "+N" pill
//   list       the same header, one word per full-width row — more meaning
//              shows per word
//   spotlight  one word, huge, with its reading and meaning — "word of the day"
//   quiz       a multiple-choice question for the story's viewers: the word,
//              four lettered meanings (buildStoryQuiz), and the answer printed
//              small and upside down at the bottom

export interface StoryWord {
  term: string;
  reading: string | null;
  meaningMn: string | null;
  meaningEn: string | null;
}

export type StoryStyle = "seal" | "dark" | "paper";
export type StoryLang = "mn" | "en" | "both";
export type StoryLayout = "grid" | "list" | "spotlight" | "quiz";
export const STORY_LAYOUTS: StoryLayout[] = ["grid", "list", "spotlight", "quiz"];

export interface StoryCard {
  /** Small line over the heading, e.g. the date or "shared deck". */
  kicker: string;
  heading: string;
  /** Big numbers under the heading: "15 / үг санасан". At most three. */
  numbers?: { value: string; label: string }[];
  words: StoryWord[];
  /** How many words there are in all; the rest show as "+N" after the grid. */
  total?: number;
  moreLabel?: (n: number) => string;
  /** Where to go, printed at the bottom (a link sticker can't be drawn). */
  footer?: string;
  style?: StoryStyle;
  lang?: StoryLang;
  layout?: StoryLayout;
  /** Which word spotlight/quiz use, and the quiz's answer slot — bump it for
   *  "another word". */
  seed?: number;
  /** Quiz copy: the question line and the label of the upside-down answer. */
  quizPrompt?: string;
  quizAnswer?: string;
}

export const STORY_W = 1080;
/** Most words a card ever shows (fewer when the screen is short). */
export const STORY_MAX_WORDS = 12;

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

interface Palette {
  /** Whole-canvas background, top to bottom. */
  bgTop: string;
  bgBottom: string;
  /** Header band: two-stop gradient, or null to draw the header straight on
   *  the background (one continuous surface, no band seam). */
  bandTop: string | null;
  bandBottom: string | null;
  bandText: string;
  bandSoft: string;
  /** The word cards. */
  card: string;
  cardLine: string;
  term: string;
  reading: string;
  meaning: string;
  accent: string;
  pill: string;
  pillText: string;
  /** Corner decoration: a soft filled disc, or an ensō-like ring. */
  deco: { kind: "disc" | "ring"; color: string };
  /** Card drop shadow. */
  shadow: string;
}

// Each style is one continuous surface — that's what made "dark" look right
// and the other two look patched together (a blue band over a beige page; a
// white-on-cream card that had no contrast or colour of its own).
const PALETTES: Record<StoryStyle, Palette> = {
  // Deep seal blue, frosted-glass cards, white type.
  seal: {
    bgTop: "#2c72cc",
    bgBottom: "#0f3672",
    bandTop: null,
    bandBottom: null,
    bandText: "#ffffff",
    bandSoft: "rgba(255,255,255,0.72)",
    card: "rgba(255,255,255,0.11)",
    cardLine: "rgba(255,255,255,0.20)",
    term: "#ffffff",
    reading: "rgba(214,230,252,0.72)",
    meaning: "rgba(255,255,255,0.94)",
    accent: "#9fc6f7",
    pill: "#ffffff",
    pillText: "#184f95",
    deco: { kind: "disc", color: "rgba(255,255,255,0.07)" },
    shadow: "rgba(4,20,48,0.30)",
  },
  dark: {
    bgTop: "#14181e",
    bgBottom: "#14181e",
    bandTop: "#0f1216",
    bandBottom: "#1b2129",
    bandText: "#f3f1ec",
    bandSoft: "rgba(243,241,236,0.7)",
    card: "#1f252e",
    cardLine: "rgba(255,255,255,0.06)",
    term: "#f3f1ec",
    reading: "#9aa3ae",
    meaning: "#d4d0c8",
    accent: "#6fa3e6",
    pill: "#2f6bb8",
    pillText: "#ffffff",
    deco: { kind: "disc", color: "rgba(255,255,255,0.06)" },
    shadow: "rgba(0,0,0,0.10)",
  },
  // Warm washi paper with a vermilion seal accent (the hanko itself).
  paper: {
    bgTop: "#f8f2e6",
    bgBottom: "#eee2cc",
    bandTop: null,
    bandBottom: null,
    bandText: "#1f2933",
    bandSoft: "#b8402c",
    card: "#fffdf8",
    cardLine: "rgba(120,90,50,0.13)",
    term: "#1c232b",
    reading: "#8c7f6c",
    meaning: "#363d46",
    accent: "#c8442f",
    pill: "#c8442f",
    pillText: "#fffaf2",
    deco: { kind: "ring", color: "rgba(200,68,47,0.10)" },
    shadow: "rgba(110,80,40,0.16)",
  },
};

// Japanese system gothics after the text face: the canvas has no page fonts
// of its own, and a Latin-only face would draw tofu for every kanji.
const JP_FALLBACK =
  '"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", "Noto Sans CJK JP", "Yu Gothic", "Meiryo", system-ui, sans-serif';

// The face for Latin and Cyrillic, set by renderStoryCard. It has to be a
// font with the full Mongolian Cyrillic set (Ө ө Ү ү): with a Japanese font
// first, those two letters were filled in from a different font and stood
// out mid-word.
let textFamily: string | null = null;

function font(weight: number, size: number) {
  return `${weight} ${size}px ${textFamily ? `${textFamily}, ` : ""}${JP_FALLBACK}`;
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

/**
 * Up to [maxLines] lines that fit [width] (as [measure] reports it), breaking
 * at spaces — or inside a word that's longer than a whole line. If text is
 * left over, the last line ends in "…". Pure, so storyCard.test.ts pins it.
 */
export function wrapLines(measure: (s: string) => number, text: string, width: number, maxLines: number): string[] {
  const tokens = text.trim().split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let cur = "";
  let i = 0;
  let truncated = false;
  while (i < tokens.length) {
    const w = tokens[i];
    const next = cur ? `${cur} ${w}` : w;
    if (measure(next) <= width) {
      cur = next;
      i++;
      continue;
    }
    if (cur) {
      lines.push(cur);
      cur = "";
      if (lines.length === maxLines) {
        truncated = true;
        break;
      }
      continue;
    }
    // A single word wider than the line: take as many characters as fit.
    const chars = [...w];
    let part = "";
    let j = 0;
    while (j < chars.length && measure(part + chars[j]) <= width) part += chars[j++];
    if (!part) part = chars[j++];
    lines.push(part);
    const rest = chars.slice(j).join("");
    if (rest) tokens[i] = rest;
    else i++;
    if (lines.length === maxLines) {
      truncated = i < tokens.length;
      break;
    }
  }
  if (cur) {
    if (lines.length < maxLines) lines.push(cur);
    else truncated = true;
  }
  if (truncated && lines.length) {
    let last = lines[lines.length - 1];
    while (last.length > 1 && measure(last + "…") > width) last = last.slice(0, -1);
    lines[lines.length - 1] = last.replace(/[\s,;·]+$/, "") + "…";
  }
  return lines;
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

function meaningOf(w: StoryWord, lang: StoryLang): string[] {
  const mn = w.meaningMn?.trim() || null;
  const en = w.meaningEn?.trim() || null;
  if (lang === "mn") return [mn ?? en ?? ""].filter(Boolean);
  if (lang === "en") return [en ?? mn ?? ""].filter(Boolean);
  return [mn, en].filter((x): x is string => !!x);
}

/** The one meaning a quiz option shows: Mongolian first unless English is asked. */
function quizMeaning(w: StoryWord, lang: StoryLang): string {
  const mn = w.meaningMn?.trim() || "";
  const en = w.meaningEn?.trim() || "";
  return lang === "en" ? en || mn : mn || en;
}

export interface StoryQuiz {
  word: StoryWord;
  options: string[];
  /** Index of the right option (0–3 = A–D). */
  answer: number;
}

/**
 * A four-option question from the card's own words, deterministic in `seed`
 * so the preview and the shared image are the same. The word is
 * `candidates[seed % n]`; the wrong options are the next words' meanings in
 * order (skipping repeats of the right one); the right one sits in slot
 * `(3·seed + 1) % 4`. Null when fewer than four words have a distinct meaning.
 * Pure — storyCard.test.ts and mobile's story_card_test.dart pin the same cases.
 */
export function buildStoryQuiz(words: StoryWord[], lang: StoryLang, seed: number): StoryQuiz | null {
  const cands = words.filter((w) => quizMeaning(w, lang));
  const n = cands.length;
  if (n < 4) return null;
  const s = Math.abs(Math.trunc(seed));
  const q = s % n;
  const right = quizMeaning(cands[q], lang);
  const wrong: string[] = [];
  for (let j = 1; j < n && wrong.length < 3; j++) {
    const m = quizMeaning(cands[(q + j) % n], lang);
    if (m !== right && !wrong.includes(m)) wrong.push(m);
  }
  if (wrong.length < 3) return null;
  const answer = (3 * s + 1) % 4;
  const options = [...wrong];
  options.splice(answer, 0, right);
  return { word: cands[q], options, answer };
}

export function drawStoryCard(ctx: CanvasRenderingContext2D, card: StoryCard) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 72;
  const p = PALETTES[card.style ?? "seal"];
  const lang = card.lang ?? "mn";
  ctx.textBaseline = "alphabetic";
  ctx.textAlign = "left";

  const bg = ctx.createLinearGradient(0, 0, 0, H);
  bg.addColorStop(0, p.bgTop);
  bg.addColorStop(1, p.bgBottom);
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, W, H);

  const layout = card.layout ?? "grid";
  if (layout === "spotlight") return drawSpotlight(ctx, card, p, lang);
  if (layout === "quiz") {
    const quiz = buildStoryQuiz(card.words, lang, card.seed ?? 0);
    // Too few words for four options: the spotlight of the same word instead.
    return quiz ? drawQuiz(ctx, card, p, quiz) : drawSpotlight(ctx, card, p, lang);
  }

  // ---- Header band ----
  ctx.font = font(800, 92);
  const headLines = wrapLines((s) => ctx.measureText(s).width, card.heading, W - 2 * M, 2);
  const numbers = (card.numbers ?? []).slice(0, 3);
  const bandH = 190 + 40 + headLines.length * 104 + (numbers.length ? 200 : 0) + 30;
  if (p.bandTop && p.bandBottom) {
    const band = ctx.createLinearGradient(0, 0, W, bandH);
    band.addColorStop(0, p.bandTop);
    band.addColorStop(1, p.bandBottom);
    ctx.fillStyle = band;
    ctx.fillRect(0, 0, W, bandH);
  }
  drawDeco(ctx, p);

  let y = 190;
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 34);
  ctx.fillText(clip(ctx, card.kicker.toUpperCase(), W - 2 * M), M, y);
  y += 40;
  ctx.fillStyle = p.bandText;
  ctx.font = font(800, 92);
  for (const line of headLines) {
    y += 104;
    ctx.fillText(line, M, y);
  }
  if (numbers.length) {
    y += 60;
    const colW = (W - 2 * M) / numbers.length;
    numbers.forEach((n, i) => {
      const x = M + i * colW;
      ctx.fillStyle = p.bandText;
      ctx.font = font(800, fit(ctx, n.value, 800, 96, 56, colW - 24));
      ctx.fillText(n.value, x, y + 82);
      ctx.fillStyle = p.bandSoft;
      ctx.font = font(600, 30);
      ctx.fillText(clip(ctx, n.label, colW - 24), x, y + 130);
    });
  }

  if (!p.bandTop) {
    ctx.fillStyle = p.cardLine;
    ctx.fillRect(M, bandH + 4, W - 2 * M, 2);
  }

  if (layout === "list") return drawList(ctx, card, p, lang, bandH);

  // ---- Word grid ----
  const footerH = card.footer ? 150 : 0;
  const top = bandH + 56;
  const bottom = H - 70 - footerH;
  const gap = 24;
  const colW = (W - 2 * M - gap) / 2;
  // Tall enough for term + reading + a two-line meaning (both languages when
  // asked): fewer, readable tiles beat many truncated ones — the rest go in
  // the "+N" pill.
  const MIN_TILE = 300, MAX_TILE = 380, MORE_H = 110;
  const total = card.total ?? card.words.length;
  const roomRows = Math.max(1, Math.floor((bottom - top - MORE_H + gap) / (MIN_TILE + gap)));
  const words = card.words.slice(0, Math.min(STORY_MAX_WORDS, roomRows * 2));
  const rows = Math.ceil(words.length / 2);
  const more = Math.max(0, total - words.length);
  const tileH = Math.min(MAX_TILE, (bottom - top - (more ? MORE_H : 0) - (rows - 1) * gap) / Math.max(rows, 1));
  const gridH = rows * tileH + (rows - 1) * gap;
  // A short grid sits a little lower rather than hugging the band.
  let gy = top + Math.max(0, (bottom - top - gridH - (more ? MORE_H : 0)) / 4);

  words.forEach((w, i) => {
    const x = M + (i % 2) * (colW + gap);
    const ty = gy + Math.floor(i / 2) * (tileH + gap);
    ctx.save();
    ctx.shadowColor = p.shadow;
    ctx.shadowBlur = 30;
    ctx.shadowOffsetY = 8;
    ctx.fillStyle = p.card;
    roundRect(ctx, x, ty, colW, tileH, 30);
    ctx.fill();
    ctx.restore();
    ctx.strokeStyle = p.cardLine;
    ctx.lineWidth = 2;
    roundRect(ctx, x, ty, colW, tileH, 30);
    ctx.stroke();
    // Accent tick, top-left.
    ctx.fillStyle = p.accent;
    roundRect(ctx, x + 34, ty + 34, 44, 8, 4);
    ctx.fill();

    const pad = 34;
    const inner = colW - 2 * pad;
    let ly = ty + 34 + 22;
    const ts = fit(ctx, w.term, 800, 72, 40, inner);
    ctx.fillStyle = p.term;
    ctx.font = font(800, ts);
    ly += ts;
    ctx.fillText(clip(ctx, w.term, inner), x + pad, ly);
    const reading = w.reading && w.reading !== w.term ? w.reading : "";
    if (reading) {
      ctx.fillStyle = p.reading;
      ctx.font = font(500, 30);
      ly += 44;
      ctx.fillText(clip(ctx, reading, inner), x + pad, ly);
    }
    const meanings = meaningOf(w, lang);
    if (meanings.length) {
      ly += 14;
      // Lines left in the tile, shared out: the first meaning gets up to two,
      // the second (English, when both are shown) what's left, up to two.
      let room = Math.max(1, Math.floor((ty + tileH - 30 - ly) / 40));
      meanings.forEach((m, mi) => {
        if (room <= 0) return;
        const size = mi === 0 ? 32 : 28;
        ctx.fillStyle = mi === 0 ? p.meaning : p.reading;
        ctx.font = font(mi === 0 ? 600 : 500, size);
        const take = Math.min(2, mi === 0 && meanings.length === 2 && room <= 2 ? 1 : room);
        for (const line of wrapLines((s) => ctx.measureText(s).width, m, inner, take)) {
          ly += 40;
          ctx.fillText(line, x + pad, ly);
          room--;
        }
      });
    }
  });

  gy += gridH;
  if (more > 0) drawMorePill(ctx, p, card, more, gy);

  // ---- Footer: where to go (the deck link). Nothing at all without one. ----
  if (!card.footer) return;
  const fy = H - footerH - 40;
  ctx.font = font(700, fit(ctx, card.footer, 700, 40, 24, W - 2 * M - 80));
  const fw = Math.min(W - 2 * M, ctx.measureText(card.footer).width + 80);
  ctx.fillStyle = p.card;
  roundRect(ctx, (W - fw) / 2, fy, fw, 96, 48);
  ctx.fill();
  ctx.strokeStyle = p.cardLine;
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = p.accent;
  ctx.textAlign = "center";
  ctx.fillText(clip(ctx, card.footer, fw - 60), W / 2, fy + 62);
  ctx.textAlign = "left";
}

// Decoration in the corner — depth without a logo. The ring is open at the
// bottom-left, like a brushed ensō.
function drawDeco(ctx: CanvasRenderingContext2D, p: Palette) {
  const W = ctx.canvas.width, H = ctx.canvas.height;
  if (p.deco.kind === "disc") {
    ctx.fillStyle = p.deco.color;
    ctx.beginPath();
    ctx.arc(W - 40, 120, 300, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(-60, H - 160, 260, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.strokeStyle = p.deco.color;
    ctx.lineCap = "round";
    ctx.lineWidth = 46;
    ctx.beginPath();
    ctx.arc(W - 80, 210, 250, Math.PI * 0.85, Math.PI * 2.6);
    ctx.stroke();
    ctx.lineCap = "butt";
  }
}

function drawMorePill(ctx: CanvasRenderingContext2D, p: Palette, card: StoryCard, more: number, y: number) {
  const W = ctx.canvas.width;
  const label = (card.moreLabel ?? ((n: number) => `+${n}`))(more);
  ctx.font = font(800, 40);
  const pw = ctx.measureText(label).width + 80;
  ctx.fillStyle = p.pill;
  roundRect(ctx, (W - pw) / 2, y + 34, pw, 72, 36);
  ctx.fill();
  ctx.fillStyle = p.pillText;
  ctx.textAlign = "center";
  ctx.fillText(label, W / 2, y + 84);
  ctx.textAlign = "left";
}

/** A card-coloured rounded box with the palette's shadow and hairline. */
function panel(ctx: CanvasRenderingContext2D, p: Palette, x: number, y: number, w: number, h: number, r: number) {
  ctx.save();
  ctx.shadowColor = p.shadow;
  ctx.shadowBlur = 30;
  ctx.shadowOffsetY = 8;
  ctx.fillStyle = p.card;
  roundRect(ctx, x, y, w, h, r);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = p.cardLine;
  ctx.lineWidth = 2;
  roundRect(ctx, x, y, w, h, r);
  ctx.stroke();
}

/** Lines of text centred on cx, the first baseline at y; returns the y after. */
function centred(ctx: CanvasRenderingContext2D, lines: string[], cx: number, y: number, lineH: number) {
  ctx.textAlign = "center";
  for (const l of lines) {
    ctx.fillText(l, cx, y);
    y += lineH;
  }
  ctx.textAlign = "left";
  return y;
}

// ---- list: one word per full-width row ----
function drawList(ctx: CanvasRenderingContext2D, card: StoryCard, p: Palette, lang: StoryLang, bandH: number) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 72;
  const top = bandH + 56, bottom = H - 70;
  const gap = 20, MORE_H = 110, MIN_ROW = 180, MAX_ROW = 230;
  const total = card.total ?? card.words.length;
  const room = Math.max(1, Math.floor((bottom - top - MORE_H + gap) / (MIN_ROW + gap)));
  const words = card.words.slice(0, Math.min(STORY_MAX_WORDS, room));
  const more = Math.max(0, total - words.length);
  const rowH = Math.min(MAX_ROW, (bottom - top - (more ? MORE_H : 0) - (words.length - 1) * gap) / Math.max(words.length, 1));
  const listH = words.length * rowH + (words.length - 1) * gap;
  let y = top + Math.max(0, (bottom - top - listH - (more ? MORE_H : 0)) / 4);
  const pad = 36, inner = W - 2 * M - 2 * pad;
  // The word on the left, its meaning on the right: a column split that
  // gives long meanings the larger share.
  const leftW = Math.round(inner * 0.4), rightX = M + pad + leftW + 28, rightW = inner - leftW - 28;

  for (const w of words) {
    panel(ctx, p, M, y, W - 2 * M, rowH, 28);
    ctx.fillStyle = p.accent;
    roundRect(ctx, M, y + 28, 8, rowH - 56, 4);
    ctx.fill();

    const reading = w.reading && w.reading !== w.term ? w.reading : "";
    const ts = fit(ctx, w.term, 800, 76, 40, leftW);
    const blockH = ts + (reading ? 48 : 0);
    let ly = y + (rowH - blockH) / 2 + ts * 0.85;
    ctx.fillStyle = p.term;
    ctx.font = font(800, ts);
    ctx.fillText(clip(ctx, w.term, leftW), M + pad, ly);
    if (reading) {
      ctx.fillStyle = p.reading;
      ctx.font = font(500, 30);
      ly += 48;
      ctx.fillText(clip(ctx, reading, leftW), M + pad, ly);
    }

    const meanings = meaningOf(w, lang);
    const lines: { text: string; size: number; weight: number; color: string }[] = [];
    let budget = Math.max(1, Math.floor((rowH - 40) / 42));
    meanings.forEach((m, mi) => {
      if (budget <= 0) return;
      const size = mi === 0 ? 34 : 28, weight = mi === 0 ? 600 : 500;
      ctx.font = font(weight, size);
      const take = Math.min(mi === 0 && meanings.length === 2 ? Math.max(1, budget - 1) : budget, 3);
      for (const t of wrapLines((s) => ctx.measureText(s).width, m, rightW, take)) {
        lines.push({ text: t, size, weight, color: mi === 0 ? p.meaning : p.reading });
        budget--;
      }
    });
    let my = y + (rowH - lines.length * 42) / 2 + 32;
    for (const l of lines) {
      ctx.fillStyle = l.color;
      ctx.font = font(l.weight, l.size);
      ctx.fillText(l.text, rightX, my);
      my += 42;
    }
    y += rowH + gap;
  }
  if (more > 0) drawMorePill(ctx, p, card, more, y - gap);
}

// ---- spotlight: one word, huge ----
function drawSpotlight(ctx: CanvasRenderingContext2D, card: StoryCard, p: Palette, lang: StoryLang) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 72;
  drawDeco(ctx, p);
  const n = card.words.length;
  if (!n) return;
  const w = card.words[Math.abs(Math.trunc(card.seed ?? 0)) % n];

  // Top: kicker and the heading, smaller than the other layouts' — the word
  // is the headline here.
  let y = 200;
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 34);
  ctx.fillText(clip(ctx, card.kicker.toUpperCase(), W - 2 * M), M, y);
  ctx.fillStyle = p.bandText;
  ctx.font = font(800, 60);
  for (const line of wrapLines((s) => ctx.measureText(s).width, card.heading, W - 2 * M, 2)) {
    y += 74;
    ctx.fillText(line, M, y);
  }

  // The word, centred in what's left, on one big card.
  const cardTop = y + 90, cardBottom = H - 230;
  panel(ctx, p, M, cardTop, W - 2 * M, cardBottom - cardTop, 48);
  const inner = W - 2 * M - 120;
  const ts = fit(ctx, w.term, 800, 280, 110, inner);
  const reading = w.reading && w.reading !== w.term ? w.reading : "";
  const meanings = meaningOf(w, lang);
  ctx.font = font(600, 52);
  const m1 = meanings[0] ? wrapLines((s) => ctx.measureText(s).width, meanings[0], inner, 3) : [];
  ctx.font = font(500, 40);
  const m2 = meanings[1] ? wrapLines((s) => ctx.measureText(s).width, meanings[1], inner, 2) : [];
  // Below the word: its descent (~0.25·size) plus a clear gap before the reading.
  const readGap = Math.round(ts * 0.25) + 76;
  const blockH = ts + (reading ? readGap : 0) + 70 + m1.length * 66 + (m2.length ? 20 + m2.length * 52 : 0);
  let cy = cardTop + (cardBottom - cardTop - blockH) / 2 + ts * 0.88;
  ctx.fillStyle = p.term;
  ctx.font = font(800, ts);
  centred(ctx, [w.term], W / 2, cy, 0);
  if (reading) {
    cy += readGap;
    ctx.fillStyle = p.accent;
    ctx.font = font(600, fit(ctx, reading, 600, 56, 32, inner));
    centred(ctx, [reading], W / 2, cy, 0);
  }
  cy += 40;
  ctx.fillStyle = p.accent;
  roundRect(ctx, W / 2 - 40, cy, 80, 8, 4);
  ctx.fill();
  cy += 30 + 52;
  ctx.fillStyle = p.meaning;
  ctx.font = font(600, 52);
  cy = centred(ctx, m1, W / 2, cy, 66);
  if (m2.length) {
    ctx.fillStyle = p.reading;
    ctx.font = font(500, 40);
    centred(ctx, m2, W / 2, cy + 20 - 14, 52);
  }

  // Bottom: the numbers as one quiet line.
  const nums = (card.numbers ?? []).slice(0, 3).map((x) => `${x.value} ${x.label}`).join("  ·  ");
  if (nums) {
    ctx.fillStyle = p.bandSoft;
    ctx.font = font(700, fit(ctx, nums, 700, 36, 24, W - 2 * M));
    centred(ctx, [nums], W / 2, H - 130, 0);
  }
}

// ---- quiz: a multiple-choice question for the viewers ----
function drawQuiz(ctx: CanvasRenderingContext2D, card: StoryCard, p: Palette, quiz: StoryQuiz) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 72;
  drawDeco(ctx, p);
  const LETTERS = ["A", "B", "C", "D"];

  let y = 200;
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 34);
  ctx.fillText(clip(ctx, card.kicker.toUpperCase(), W - 2 * M), M, y);
  ctx.fillStyle = p.bandText;
  ctx.font = font(800, 64);
  for (const line of wrapLines((s) => ctx.measureText(s).width, card.quizPrompt ?? "?", W - 2 * M, 2)) {
    y += 78;
    ctx.fillText(line, M, y);
  }

  // The question card and four options, as one block centred between the
  // prompt and the answer line, as large as the space allows.
  const reading = quiz.word.reading && quiz.word.reading !== quiz.word.term ? quiz.word.reading : "";
  const areaTop = y + 60, areaBottom = H - 200, gap = 26, between = 56;
  const avail = areaBottom - areaTop;
  const qH = Math.min(reading ? 520 : 440, Math.round(avail * 0.36));
  const oH = Math.min(210, (avail - qH - between - 3 * gap) / 4);
  const blockH = qH + between + 4 * oH + 3 * gap;
  const qTop = areaTop + Math.max(0, (avail - blockH) / 2);

  panel(ctx, p, M, qTop, W - 2 * M, qH, 44);
  const inner = W - 2 * M - 100;
  const ts = fit(ctx, quiz.word.term, 800, 230, 90, inner);
  const readGap = Math.round(ts * 0.25) + 64;
  const wordH = ts * 0.75 + (reading ? readGap : 0);
  const termY = qTop + (qH - wordH) / 2 + ts * 0.75;
  ctx.fillStyle = p.term;
  ctx.font = font(800, ts);
  centred(ctx, [quiz.word.term], W / 2, termY, 0);
  if (reading) {
    ctx.fillStyle = p.accent;
    ctx.font = font(600, fit(ctx, reading, 600, 54, 30, inner));
    centred(ctx, [reading], W / 2, termY + readGap, 0);
  }

  const oTop = qTop + qH + between;
  const textX = M + 160, textW = W - 2 * M - 160 - 44;
  const badge = Math.min(46, oH / 2 - 16);
  quiz.options.forEach((opt, i) => {
    const oy = oTop + i * (oH + gap);
    panel(ctx, p, M, oy, W - 2 * M, oH, Math.min(44, oH / 2));
    // Letter badge.
    ctx.fillStyle = p.pill;
    ctx.beginPath();
    ctx.arc(M + 84, oy + oH / 2, badge, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = p.pillText;
    ctx.font = font(800, 44);
    centred(ctx, [LETTERS[i]], M + 84, oy + oH / 2 + 15, 0);
    // Option text, up to two lines.
    ctx.font = font(600, 42);
    const lines = wrapLines((s) => ctx.measureText(s).width, opt, textW, oH > 140 ? 2 : 1);
    ctx.fillStyle = p.meaning;
    let ty = oy + (oH - lines.length * 52) / 2 + 38;
    for (const l of lines) {
      ctx.fillText(l, textX, ty);
      ty += 52;
    }
  });

  // The answer, small and upside down — turn the phone to check.
  const answer = `${card.quizAnswer ?? "Answer"}: ${LETTERS[quiz.answer]}`;
  ctx.save();
  ctx.translate(W / 2, H - 120);
  ctx.rotate(Math.PI);
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 32);
  ctx.textAlign = "center";
  ctx.fillText(answer, 0, 0);
  ctx.restore();
}

/** The card as a PNG. Waits for fonts so the first render isn't in a fallback face. */
export async function renderStoryCard(
  card: StoryCard,
  size: { width: number; height: number } = storySize(),
  /** A loaded web font with Mongolian Cyrillic (e.g. next/font's fontFamily). */
  family?: string
): Promise<Blob> {
  textFamily = family ?? null;
  try {
    // A canvas doesn't trigger web-font loading on its own: ask for every
    // weight the card draws, with the letters that matter, before drawing.
    if (family) {
      await Promise.all([500, 600, 700, 800].map((w) => document.fonts.load(`${w} 40px ${family}`, "Өө Үү Aa")));
    }
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
