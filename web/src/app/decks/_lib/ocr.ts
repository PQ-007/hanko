"use client";

import type { Worker } from "tesseract.js";

// Japanese text from a photo, in the browser (Tesseract.js) — the web's
// stand-in for mobile's ML Kit. Measured before choosing it: 95–99% of
// characters right on clean, small and photo-like (blurred, tilted, noisy)
// renders of both horizontal and vertical text.
//
// Two models, ~3 MB each, downloaded the first time and then kept by the
// library in this browser: horizontal (jpn) first; if it isn't confident,
// vertical (jpn_vert), keeping whichever is surer. The right model scored
// 85–92 on every test image and the wrong one 11–25, so 60 splits them.
// Both run with automatic page layout: Tesseract's single-block default
// reads vertical text as garbage even with the vertical model.
//
// Loaded on demand, so no other page carries it.

const CONFIDENT = 60;
/** Phone photos are 4000px+; recognition is no better above this, only slower. */
const MAX_SIDE = 2000;

const workers = new Map<string, Promise<Worker>>();

async function worker(lang: "jpn" | "jpn_vert", onProgress?: (p: number) => void): Promise<Worker> {
  let w = workers.get(lang);
  if (!w) {
    w = (async () => {
      const { createWorker, PSM } = await import("tesseract.js");
      const created = await createWorker(lang, 1, {
        logger: (m: { status: string; progress: number }) => {
          if (m.status === "recognizing text") progressSink?.(m.progress);
        },
      });
      await created.setParameters({ tessedit_pageseg_mode: PSM.AUTO });
      return created;
    })();
    workers.set(lang, w);
    w.catch(() => workers.delete(lang));
  }
  progressSink = onProgress;
  return w;
}

let progressSink: ((p: number) => void) | undefined;

/** The photo at a sensible size, as something Tesseract reads. */
async function prepare(image: Blob): Promise<Blob | HTMLCanvasElement> {
  try {
    const bmp = await createImageBitmap(image);
    const scale = Math.min(1, MAX_SIDE / Math.max(bmp.width, bmp.height));
    if (scale === 1) return image;
    const c = document.createElement("canvas");
    c.width = Math.round(bmp.width * scale);
    c.height = Math.round(bmp.height * scale);
    c.getContext("2d")!.drawImage(bmp, 0, 0, c.width, c.height);
    return c;
  } catch {
    return image;
  }
}

export interface OcrResult {
  /** Lines (columns, for vertical text) in reading order, spaces removed. */
  lines: string[];
  confidence: number;
  vertical: boolean;
}

export async function recognizeJapanese(image: Blob, onProgress?: (p: number) => void): Promise<OcrResult> {
  const input = await prepare(image);
  const h = (await (await worker("jpn", onProgress)).recognize(input)).data;
  let best = { data: h, vertical: false };
  if (h.confidence < CONFIDENT) {
    const v = (await (await worker("jpn_vert", onProgress)).recognize(input)).data;
    if (v.confidence > h.confidence) best = { data: v, vertical: true };
  }
  return {
    // Tesseract spaces out CJK characters; Japanese has no spaces to keep.
    lines: best.data.text
      .split("\n")
      .map((l) => l.replace(/\s+/g, ""))
      .filter(Boolean),
    confidence: best.data.confidence,
    vertical: best.vertical,
  };
}
