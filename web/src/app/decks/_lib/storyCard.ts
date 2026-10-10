// A full-screen, unbranded story image (Instagram / Facebook stories) drawn on
// a canvas in the browser — no server, no package. Sized to the phone it's made
// on (storySize), so it fills that screen edge to edge. Two uses: "today's
// words" from the stats page, and a shared deck's invitation from the deck
// share dialog. mobile/lib/features/share/story_card.dart is a port.
//
// Five layouts (StoryLayout):
//   achievement  Strava-style: your hero mid-swing in a burst, one huge
//              number, a stat row, the week as a streak chain, word chips
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
export type StoryLayout = "achievement" | "grid" | "list" | "spotlight" | "quiz";
export const STORY_LAYOUTS: StoryLayout[] = ["achievement", "grid", "list", "spotlight", "quiz"];

/** The player's Monster Hunt hero, drawn as the story's mascot. */
export interface StoryMascot {
  slug: string;
  /** What the speech bubble says (short — it wraps to two lines at most). */
  says?: string | null;
}

/** One day of the streak chain, oldest first, today last. */
export interface StoryDay {
  label: string;
  active: boolean;
}

/** Sprite frames the renderer draws, loaded by renderStoryCard (or a test). */
export interface StoryArt {
  /** A 100×100 frame strip; frame 0 is drawn. */
  idle: CanvasImageSource | null;
  /** A swing, for the achievement burst. */
  cheer: CanvasImageSource | null;
  cheerFrame: number;
}

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
  mascot?: StoryMascot;
  /** What the mascot says when the layout has nothing of its own to say. */
  bubble?: string;
  /** The streak chain for the achievement layout (7 days, today last). */
  week?: StoryDay[];
}

// Instagram draws its own chrome over a story: the progress bars and profile
// row at the top, the reply bar at the bottom. Nothing that matters goes there.
const safeTop = (H: number) => Math.max(190, Math.round(H * 0.105));
const safeBottom = (H: number) => H - Math.max(70, Math.round(H * 0.09));

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
  /** The achievement layout's big number. */
  metric: string;
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
    metric: "#ffffff",
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
    metric: "#6fa3e6",
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
    metric: "#c8442f",
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

export function drawStoryCard(ctx: CanvasRenderingContext2D, card: StoryCard, art: StoryArt | null = null) {
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
  drawWatermark(ctx, p, card);
  const says = card.mascot?.says?.trim() || null;

  const layout = card.layout ?? "grid";
  if (layout === "achievement") return drawAchievement(ctx, card, p, art, says);
  if (layout === "spotlight") return drawSpotlight(ctx, card, p, lang, art, says);
  if (layout === "quiz") {
    const quiz = buildStoryQuiz(card.words, lang, card.seed ?? 0);
    // Too few words for four options: the spotlight of the same word instead.
    return quiz ? drawQuiz(ctx, card, p, quiz, art, says) : drawSpotlight(ctx, card, p, lang, art, says);
  }

  // ---- Header band ----
  // With a mascot, the heading leaves the top-right corner to it.
  const y0 = safeTop(H);
  const mascotW = art?.idle ? 300 : 0;
  ctx.font = font(800, 92);
  const headLines = wrapLines((s) => ctx.measureText(s).width, card.heading, W - 2 * M - mascotW, 2);
  const numbers = (card.numbers ?? []).slice(0, 3);
  const afterHead = y0 + 40 + headLines.length * 104;
  // The numbers row starts below the mascot's feet.
  const numsAt = mascotW ? Math.max(afterHead, y0 + 243) : afterHead;
  const bandH = numbers.length ? numsAt + 230 : Math.max(afterHead + 30, mascotW ? y0 + 330 : 0);
  if (p.bandTop && p.bandBottom) {
    const band = ctx.createLinearGradient(0, 0, W, bandH);
    band.addColorStop(0, p.bandTop);
    band.addColorStop(1, p.bandBottom);
    ctx.fillStyle = band;
    ctx.fillRect(0, 0, W, bandH);
  }
  drawDeco(ctx, p);

  let y = y0;
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 34);
  ctx.fillText(clip(ctx, card.kicker.toUpperCase(), W - 2 * M - mascotW), M, y);
  y += 40;
  ctx.fillStyle = p.bandText;
  ctx.font = font(800, 92);
  for (const line of headLines) {
    y += 104;
    ctx.fillText(line, M, y);
  }
  if (art?.idle) {
    // The hero in the corner, with something to say.
    const head = drawHero(ctx, art.idle, 0, W - M - 140, y0 + 300, 200, 260);
    if (says) drawBubble(ctx, p, says, W - M - 140, head - 10, 300);
  }
  if (numbers.length) {
    y = numsAt + 60;
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
  const bottom = safeBottom(H) - footerH;
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
  const top = bandH + 56, bottom = safeBottom(H);
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
function drawSpotlight(
  ctx: CanvasRenderingContext2D,
  card: StoryCard,
  p: Palette,
  lang: StoryLang,
  art: StoryArt | null,
  says: string | null
) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 72;
  drawDeco(ctx, p);
  const n = card.words.length;
  if (!n) return;
  const w = card.words[Math.abs(Math.trunc(card.seed ?? 0)) % n];

  // Top: kicker and the heading, smaller than the other layouts' — the word
  // is the headline here.
  let y = safeTop(H);
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
  const cardTop = y + 90, cardBottom = safeBottom(H) - 110;
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

  // The hero peeks over the card's bottom-left corner.
  if (art?.idle) {
    const head = drawHero(ctx, art.idle, 0, M + 150, cardBottom - 28, 230, 240);
    if (says) drawBubble(ctx, p, says, M + 170, head - 10, 380);
  }

  // Bottom: the numbers as one quiet line.
  const nums = (card.numbers ?? []).slice(0, 3).map((x) => `${x.value} ${x.label}`).join("  ·  ");
  if (nums) {
    ctx.fillStyle = p.bandSoft;
    ctx.font = font(700, fit(ctx, nums, 700, 36, 24, W - 2 * M));
    centred(ctx, [nums], W / 2, safeBottom(H) - 20, 0);
  }
}

// ---- quiz: a multiple-choice question for the viewers ----
function drawQuiz(
  ctx: CanvasRenderingContext2D,
  card: StoryCard,
  p: Palette,
  quiz: StoryQuiz,
  art: StoryArt | null,
  says: string | null
) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 72;
  drawDeco(ctx, p);
  const LETTERS = ["A", "B", "C", "D"];

  const y0 = safeTop(H);
  const mascotW = art?.idle ? 250 : 0;
  let y = y0;
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 34);
  ctx.fillText(clip(ctx, card.kicker.toUpperCase(), W - 2 * M - mascotW), M, y);
  ctx.fillStyle = p.bandText;
  ctx.font = font(800, 64);
  for (const line of wrapLines((s) => ctx.measureText(s).width, card.quizPrompt ?? "?", W - 2 * M - mascotW, 2)) {
    y += 78;
    ctx.fillText(line, M, y);
  }
  if (art?.idle) {
    // No bubble here: the prompt beside it already asks the question.
    void says;
    drawHero(ctx, art.idle, 0, W - M - 110, y0 + 190, 200, 220);
    y = Math.max(y, y0 + 190);
  }

  // The question card and four options, as one block centred between the
  // prompt and the answer line, as large as the space allows.
  const reading = quiz.word.reading && quiz.word.reading !== quiz.word.term ? quiz.word.reading : "";
  const areaTop = y + 60, areaBottom = safeBottom(H) - 90, gap = 26, between = 56;
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
  ctx.translate(W / 2, safeBottom(H) - 20);
  ctx.rotate(Math.PI);
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 32);
  ctx.textAlign = "center";
  ctx.fillText(answer, 0, 0);
  ctx.restore();
}

// ---- Mascot, bubble, watermark -------------------------------------------

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}
const boxes = new WeakMap<object, Map<number, Box>>();

/**
 * Where the character actually is inside its 100×100 frame. The figures fill
 * a third of the frame or less (the rest is room for swings), so sizing by
 * the frame drew a mascot the size of a stamp.
 */
function spriteBox(img: CanvasImageSource, frame: number): Box {
  const cache = boxes.get(img as object) ?? new Map<number, Box>();
  boxes.set(img as object, cache);
  const hit = cache.get(frame);
  if (hit) return hit;
  let box: Box = { x: 0, y: 0, w: 100, h: 100 };
  try {
    const c = document.createElement("canvas");
    c.width = 100;
    c.height = 100;
    const g = c.getContext("2d")!;
    g.drawImage(img, frame * 100, 0, 100, 100, 0, 0, 100, 100);
    const d = g.getImageData(0, 0, 100, 100).data;
    let x0 = 100, y0 = 100, x1 = -1, y1 = -1;
    for (let y = 0; y < 100; y++)
      for (let x = 0; x < 100; x++)
        if (d[(y * 100 + x) * 4 + 3] > 24) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
    if (x1 >= 0) box = { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
  } catch {
    // No pixel access: fall back to the whole frame.
  }
  cache.set(frame, box);
  return box;
}

/**
 * The hero, standing with its feet on (cx, footY), as tall as it can be up
 * to [maxH] × [maxW] — at a whole-number scale, so the pixel art stays crisp.
 * Returns the top of its head (where a speech bubble's tail goes).
 */
function drawHero(
  ctx: CanvasRenderingContext2D,
  img: CanvasImageSource,
  frame: number,
  cx: number,
  footY: number,
  maxH: number,
  maxW = maxH * 1.4
): number {
  const b = spriteBox(img, frame);
  const k = Math.max(1, Math.floor(Math.min(maxH / b.h, maxW / b.w)));
  const left = Math.round(cx - (b.x + b.w / 2) * k);
  const top = Math.round(footY - (b.y + b.h) * k);
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(img, frame * 100, 0, 100, 100, left, top, 100 * k, 100 * k);
  ctx.restore();
  return top + b.y * k;
}

/** A rounded speech bubble whose tail points down at (cx, tipY). */
function drawBubble(ctx: CanvasRenderingContext2D, p: Palette, text: string, cx: number, tipY: number, maxW: number) {
  const W = ctx.canvas.width;
  ctx.font = font(800, 34);
  const lines = wrapLines((s) => ctx.measureText(s).width, text, maxW - 56, 2);
  const w = Math.min(maxW, Math.max(...lines.map((l) => ctx.measureText(l).width)) + 56);
  const h = lines.length * 42 + 34;
  // Keep the bubble on the canvas; the tail still points at the speaker.
  const x = Math.max(24, Math.min(W - 24 - w, cx - w / 2));
  const y = tipY - 22 - h;
  ctx.save();
  ctx.shadowColor = p.shadow;
  ctx.shadowBlur = 24;
  ctx.shadowOffsetY = 6;
  ctx.fillStyle = p.pill;
  roundRect(ctx, x, y, w, h, Math.min(36, h / 2));
  ctx.fill();
  ctx.beginPath();
  const tx = Math.max(x + 30, Math.min(x + w - 30, cx));
  ctx.moveTo(tx - 18, y + h - 2);
  ctx.lineTo(tx, tipY);
  ctx.lineTo(tx + 18, y + h - 2);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
  ctx.fillStyle = p.pillText;
  ctx.font = font(800, 34);
  centred(ctx, lines, x + w / 2, y + 17 + 32, 42);
}

/** The first kanji of the story, giant and faint, as texture. */
function drawWatermark(ctx: CanvasRenderingContext2D, p: Palette, card: StoryCard) {
  const ch = [...(card.words[0]?.term ?? "")].find((c) => /[\u3400-\u9fff]/.test(c));
  if (!ch) return;
  const W = ctx.canvas.width, H = ctx.canvas.height;
  ctx.save();
  ctx.translate(W * 0.72, H * 0.7);
  ctx.rotate(-0.12);
  ctx.fillStyle = p.deco.color;
  ctx.font = font(900, 900);
  ctx.textAlign = "center";
  ctx.fillText(ch, 0, 300);
  ctx.restore();
}

/** Small deterministic noise, so the confetti is the same in preview and share. */
function rng(seed: number) {
  let a = (seed * 2654435761) >>> 0 || 1;
  return () => {
    a ^= a << 13;
    a ^= a >>> 17;
    a ^= a << 5;
    return ((a >>> 0) % 10000) / 10000;
  };
}

// ---- achievement: the Strava-style summary ----
function drawAchievement(ctx: CanvasRenderingContext2D, card: StoryCard, p: Palette, art: StoryArt | null, says: string | null) {
  const W = ctx.canvas.width, H = ctx.canvas.height, M = 72;
  drawDeco(ctx, p);
  const top = safeTop(H);
  let bottom = safeBottom(H);
  const numbers = card.numbers ?? [];

  // Top, centred: kicker and a modest heading.
  let y = top;
  ctx.fillStyle = p.bandSoft;
  ctx.font = font(700, 34);
  centred(ctx, [clip(ctx, card.kicker.toUpperCase(), W - 2 * M)], W / 2, y, 0);
  ctx.fillStyle = p.bandText;
  ctx.font = font(800, 64);
  for (const line of wrapLines((s) => ctx.measureText(s).width, card.heading, W - 2 * M, 2)) {
    y += 78;
    centred(ctx, [line], W / 2, y, 0);
  }
  const zoneTop = y + 40;

  // Built from the bottom up: word chips, the week, the stat row, the big
  // number — whatever is left above goes to the hero.

  // Word chips, up to two rows.
  ctx.font = font(800, 44);
  const chipH = 84, chipGap = 16, chipPad = 30;
  const rows: { text: string; w: number }[][] = [[]];
  let rowW = 0;
  for (const w of card.words.slice(0, 10)) {
    const cw = Math.min(W - 2 * M, ctx.measureText(w.term).width + 2 * chipPad);
    if (rowW + cw > W - 2 * M && rows[rows.length - 1].length) {
      if (rows.length === 2) break;
      rows.push([]);
      rowW = 0;
    }
    rows[rows.length - 1].push({ text: w.term, w: cw });
    rowW += cw + chipGap;
  }
  const chipRows = rows.filter((r) => r.length);
  if (chipRows.length) {
    const blockH = chipRows.length * chipH + (chipRows.length - 1) * chipGap;
    let cy = bottom - blockH;
    for (const r of chipRows) {
      const total = r.reduce((s, c) => s + c.w, 0) + (r.length - 1) * chipGap;
      let cx = (W - total) / 2;
      for (const c of r) {
        panel(ctx, p, cx, cy, c.w, chipH, chipH / 2);
        ctx.fillStyle = p.term;
        ctx.font = font(800, 44);
        ctx.fillText(clip(ctx, c.text, c.w - 2 * chipPad), cx + chipPad, cy + 58);
        cx += c.w + chipGap;
      }
      cy += chipH + chipGap;
    }
    bottom -= blockH + 56;
  }

  // The week as a streak chain.
  const week = card.week ?? [];
  if (week.length) {
    const r = 40, labelY = bottom - 4, cyc = labelY - 58 - r;
    const span = W - 2 * M - 2 * r;
    const step = span / Math.max(1, week.length - 1);
    const xs = week.map((_, i) => M + r + i * step);
    for (let i = 0; i + 1 < week.length; i++) {
      ctx.fillStyle = week[i].active && week[i + 1].active ? p.accent : p.cardLine;
      ctx.fillRect(xs[i], cyc - 6, step, 12);
    }
    week.forEach((d, i) => {
      const today = i === week.length - 1;
      ctx.beginPath();
      ctx.arc(xs[i], cyc, today ? r + 6 : r, 0, Math.PI * 2);
      ctx.fillStyle = d.active ? p.accent : p.card;
      ctx.fill();
      ctx.lineWidth = 4;
      ctx.strokeStyle = d.active ? p.accent : p.cardLine;
      ctx.stroke();
      if (d.active) {
        ctx.strokeStyle = p.pillText;
        ctx.lineWidth = 9;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(xs[i] - 16, cyc + 1);
        ctx.lineTo(xs[i] - 4, cyc + 13);
        ctx.lineTo(xs[i] + 18, cyc - 12);
        ctx.stroke();
        ctx.lineCap = "butt";
      }
      ctx.fillStyle = today ? p.bandText : p.bandSoft;
      ctx.font = font(today ? 800 : 600, 28);
      centred(ctx, [d.label], xs[i], labelY, 0);
    });
    bottom = cyc - r - 56;
  }

  // The stat row: the second and third numbers, divided like a run summary.
  const rest = numbers.slice(1, 3);
  if (rest.length) {
    const h = 176;
    panel(ctx, p, M, bottom - h, W - 2 * M, h, 36);
    const colW = (W - 2 * M) / rest.length;
    rest.forEach((n, i) => {
      const cx = M + colW * i + colW / 2;
      if (i > 0) {
        ctx.fillStyle = p.cardLine;
        ctx.fillRect(M + colW * i, bottom - h + 34, 2, h - 68);
      }
      ctx.fillStyle = p.term;
      ctx.font = font(800, fit(ctx, n.value, 800, 76, 40, colW - 40));
      centred(ctx, [n.value], cx, bottom - h + 92, 0);
      ctx.fillStyle = p.reading;
      ctx.font = font(600, 30);
      centred(ctx, [clip(ctx, n.label, colW - 40)], cx, bottom - h + 140, 0);
    });
    bottom -= h + 48;
  }

  // The one big number.
  const hero = numbers[0] ?? { value: String(card.total ?? card.words.length), label: "" };
  if (hero.label) {
    ctx.fillStyle = p.bandSoft;
    ctx.font = font(700, 44);
    centred(ctx, [clip(ctx, hero.label, W - 2 * M)], W / 2, bottom, 0);
    bottom -= 64;
  }
  const vs = fit(ctx, hero.value, 900, 300, 140, W - 2 * M);
  ctx.fillStyle = p.metric;
  ctx.font = font(900, vs);
  centred(ctx, [hero.value], W / 2, bottom, 0);
  bottom -= vs * 0.78 + 30;

  // The hero in a burst of rays and confetti, in whatever room is left.
  const zoneH = bottom - zoneTop;
  if (zoneH < 160) return;
  const cx = W / 2, cy = zoneTop + zoneH / 2 + 20;
  const R = Math.min(560, zoneH * 0.75);
  ctx.save();
  ctx.fillStyle = p.deco.color;
  for (let i = 0; i < 18; i += 2) {
    const a0 = (i / 18) * Math.PI * 2, a1 = ((i + 1) / 18) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, R, a0, a1);
    ctx.closePath();
    ctx.fill();
  }
  const rand = rng(card.seed ?? 7);
  const colours = [p.accent, p.pill, p.bandSoft, p.meaning];
  for (let i = 0; i < 28; i++) {
    const a = rand() * Math.PI * 2, d = R * (0.45 + rand() * 0.6);
    ctx.save();
    ctx.translate(cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.8);
    ctx.rotate(rand() * Math.PI);
    ctx.fillStyle = colours[i % colours.length];
    roundRect(ctx, -9, -4, 18 + rand() * 14, 9, 4);
    ctx.fill();
    ctx.restore();
  }
  ctx.restore();

  const sprite = art?.cheer ?? art?.idle ?? null;
  if (sprite) {
    // Feet a little below the burst's centre, so the figure fills it.
    const maxH = Math.min(560, zoneH * 0.7);
    const foot = cy + maxH * 0.55;
    const head = drawHero(ctx, sprite, art?.cheer ? art.cheerFrame : 0, cx, foot, maxH, W - 2 * M);
    if (says) drawBubble(ctx, p, says, Math.min(W - 220, cx + 120), Math.max(zoneTop + 120, head - 10), 440);
  }
}

/**
 * The mascot's frames: idle, and a swing caught mid-motion for the
 * achievement burst (the strongest attack the hero has, at ~60% through).
 */
export async function loadStoryArt(slug: string, frames: Partial<Record<string, { frames: number }>>): Promise<StoryArt> {
  const load = (pose: string) =>
    new Promise<HTMLImageElement | null>((resolve) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);
      img.src = `/battle/characters/${slug}/${pose}.png`;
    });
  const pose = ["attack02", "attack01"].find((k) => frames[k]) ?? null;
  const [idle, cheer] = await Promise.all([load("idle"), pose ? load(pose) : Promise.resolve(null)]);
  const n = pose ? (frames[pose]?.frames ?? 1) : 1;
  return { idle, cheer, cheerFrame: Math.min(n - 1, Math.floor(n * 0.6)) };
}

/** The card as a PNG. Waits for fonts so the first render isn't in a fallback face. */
export async function renderStoryCard(
  card: StoryCard,
  size: { width: number; height: number } = storySize(),
  /** A loaded web font with Mongolian Cyrillic (e.g. next/font's fontFamily). */
  family?: string,
  art: StoryArt | null = null
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
  drawStoryCard(ctx, card, art);
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("toBlob failed"))), "image/png")
  );
}
