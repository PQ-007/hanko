"use client";

import { useEffect, useRef, useState } from "react";
import { KANJI_BOX, type KanjiStrokes, type Polyline, type Pt } from "../_lib/strokes";

const RED = "#dc2626";
const SEAL = "#256abf";

/**
 * The writing square (mobile's WritingPad): a practice-paper cross, a guide of
 * the kanji's strokes (all, some or none), an animated stroke-order demo, the
 * answer in red after a miss with the wrong stroke marked, and the learner's
 * own strokes on top. Mouse, touch and pen all draw (pointer events).
 *
 * Ink is kept in pad pixels — the grader scales it onto the kanji, so the
 * pad's size doesn't matter.
 */
export default function WritingPad({
  strokes,
  guideCount,
  answer = false,
  demo = false,
  demoKey = 0,
  ink,
  onInk,
  locked = false,
  borderColor,
  badInk = null,
  focusStroke = null,
  showCount = true,
}: {
  strokes: KanjiStrokes | null;
  guideCount: number;
  answer?: boolean;
  demo?: boolean;
  /** Changing it replays the demo. */
  demoKey?: number;
  ink: Polyline[];
  onInk: (ink: Polyline[]) => void;
  locked?: boolean;
  borderColor?: string;
  badInk?: number | null;
  focusStroke?: number | null;
  showCount?: boolean;
}) {
  const wrap = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const [size, setSize] = useState(320);
  const [demoProgress, setDemoProgress] = useState<number | null>(null);
  const drawing = useRef<Polyline | null>(null);

  // Square, as wide as its container allows (capped so a desktop pad isn't a wall).
  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setSize(Math.min(440, Math.floor(e.contentRect.width))));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // The stroke-order demo: about half a second a stroke.
  useEffect(() => {
    if (!demo || !strokes) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- reset when the demo is off
      setDemoProgress(null);
      return;
    }
    const total = strokes.polylines.length;
    const start = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const p = ((now - start) / 500) % (total + 2);
      if (p >= total) {
        setDemoProgress(null);
        return;
      }
      setDemoProgress(p);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [demo, strokes, demoKey]);

  useEffect(() => {
    const c = canvas.current;
    const ctx = c?.getContext("2d");
    if (!c || !ctx) return;
    const dpr = window.devicePixelRatio || 1;
    c.width = size * dpr;
    c.height = size * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, size, size);

    // Practice-paper cross (十字), dashed.
    // Ink, guide and grid follow the theme: dark ink on a dark pad would be
    // invisible.
    const dark = document.documentElement.dataset.theme === "dark";
    const INK = dark ? "#ece9e2" : "#1f2933";
    ctx.strokeStyle = dark ? "rgba(236,233,226,0.14)" : "rgba(120,110,90,0.25)";
    ctx.lineWidth = 1;
    ctx.setLineDash([8, 8]);
    ctx.beginPath();
    ctx.moveTo(0, size / 2);
    ctx.lineTo(size, size / 2);
    ctx.moveTo(size / 2, 0);
    ctx.lineTo(size / 2, size);
    ctx.stroke();
    ctx.setLineDash([]);

    const scale = size / KANJI_BOX;
    const width = size * 0.045;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    const line = (pts: Polyline, upTo = Infinity) => {
      if (!pts.length) return;
      ctx.beginPath();
      ctx.moveTo(pts[0][0] * scale, pts[0][1] * scale);
      let walked = 0;
      for (let k = 1; k < pts.length; k++) {
        const seg = Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]);
        if (walked + seg > upTo) {
          const t = (upTo - walked) / seg;
          ctx.lineTo(
            (pts[k - 1][0] + (pts[k][0] - pts[k - 1][0]) * t) * scale,
            (pts[k - 1][1] + (pts[k][1] - pts[k - 1][1]) * t) * scale
          );
          break;
        }
        ctx.lineTo(pts[k][0] * scale, pts[k][1] * scale);
        walked += seg;
      }
      ctx.stroke();
    };
    const polyLength = (pts: Polyline) =>
      pts.reduce((s, p, k) => (k ? s + Math.hypot(p[0] - pts[k - 1][0], p[1] - pts[k - 1][1]) : 0), 0);

    if (strokes && guideCount > 0) {
      ctx.strokeStyle = answer ? "rgba(220,38,38,0.3)" : dark ? "rgba(236,233,226,0.16)" : "rgba(31,41,51,0.13)";
      ctx.lineWidth = width;
      strokes.polylines.slice(0, guideCount).forEach((p) => line(p));
      if (answer && focusStroke !== null && focusStroke < strokes.polylines.length) {
        ctx.strokeStyle = "rgba(220,38,38,0.85)";
        line(strokes.polylines[focusStroke]);
      }
      // Stroke numbers at each stroke's start.
      ctx.font = `${Math.round(size * 0.035)}px sans-serif`;
      ctx.fillStyle = answer ? RED : dark ? "rgba(185,179,168,0.9)" : "rgba(102,96,83,0.9)";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      strokes.starts.slice(0, guideCount).forEach((s: Pt, i) => ctx.fillText(String(i + 1), s[0] * scale - 4, s[1] * scale));
    }
    if (strokes && demoProgress !== null) {
      ctx.strokeStyle = SEAL;
      ctx.lineWidth = width;
      strokes.polylines.forEach((p, i) => {
        if (i > demoProgress) return;
        const frac = Math.min(1, demoProgress - i);
        line(p, frac >= 1 ? Infinity : polyLength(p) * frac);
      });
    }

    ink.forEach((s, i) => {
      ctx.strokeStyle = i === badInk ? RED : INK;
      ctx.fillStyle = ctx.strokeStyle;
      ctx.lineWidth = width * 0.8;
      if (s.length === 1) {
        ctx.beginPath();
        ctx.arc(s[0][0], s[0][1], width * 0.4, 0, Math.PI * 2);
        ctx.fill();
        return;
      }
      ctx.beginPath();
      ctx.moveTo(s[0][0], s[0][1]);
      for (const p of s.slice(1)) ctx.lineTo(p[0], p[1]);
      ctx.stroke();
    });
  }, [size, strokes, guideCount, answer, focusStroke, demoProgress, ink, badInk]);

  const at = (e: React.PointerEvent): Pt => {
    const r = canvas.current!.getBoundingClientRect();
    return [e.clientX - r.left, e.clientY - r.top];
  };

  return (
    <div ref={wrap} className="mx-auto w-full max-w-[440px]">
      <div
        className="relative overflow-hidden rounded-2xl border-2 bg-surface"
        style={{ width: size, height: size, borderColor: borderColor ?? "var(--color-line)" }}
      >
        <canvas
          ref={canvas}
          style={{ width: size, height: size, touchAction: "none" }}
          className="block cursor-crosshair"
          onPointerDown={(e) => {
            if (locked) return;
            e.currentTarget.setPointerCapture(e.pointerId);
            drawing.current = [at(e)];
            onInk([...ink, drawing.current]);
          }}
          onPointerMove={(e) => {
            if (!drawing.current || locked) return;
            drawing.current = [...drawing.current, at(e)];
            onInk([...ink.slice(0, -1), drawing.current]);
          }}
          onPointerUp={() => {
            drawing.current = null;
          }}
          onPointerCancel={() => {
            drawing.current = null;
          }}
        />
        {showCount && strokes && (
          <span
            className={`pointer-events-none absolute bottom-2 right-3 text-xs font-bold ${
              ink.length > strokes.polylines.length ? "text-red-600" : "text-ink-mute"
            }`}
          >
            {ink.length} / {strokes.polylines.length}
          </span>
        )}
      </div>
    </div>
  );
}
