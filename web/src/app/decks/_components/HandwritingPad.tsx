"use client";

import { useEffect, useRef, useState } from "react";
import { Loader2, PenLine, Trash2, Undo2 } from "@/ui/icons";
import WritingPad from "../writing/_components/WritingPad";
import type { Polyline } from "../writing/_lib/strokes";
import { recognizeKanji } from "../_lib/handwriting";
import { T } from "../_lib/strings";

// How long the pen has to rest before the ink is sent. Short enough that the
// candidates feel live, long enough not to send every half-stroke.
const SETTLE_MS = 300;

/**
 * Draw one character, pick it from the candidates, draw the next. Used by the
 * add-word dialog for kanji the user can read off a page but can't type.
 *
 * Recognition is remote (see _lib/handwriting.ts); this only holds the ink
 * and the latest answer. A stale answer can't land on newer ink: each request
 * is aborted as soon as the ink changes again.
 */
export default function HandwritingPad({
  preContext,
  onPick,
}: {
  /** Text before the caret, so the recogniser ranks by what makes a word. */
  preContext: string;
  onPick: (s: string) => void;
}) {
  const wrap = useRef<HTMLDivElement>(null);
  const [ink, setInk] = useState<Polyline[]>([]);
  const [candidates, setCandidates] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (ink.length === 0) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- cleared pad, nothing to recognise
      setCandidates([]);
      setFailed(false);
      setBusy(false);
      return;
    }
    const ctl = new AbortController();
    const timer = setTimeout(async () => {
      const side = wrap.current?.clientWidth ?? 200;
      setBusy(true);
      try {
        setCandidates(await recognizeKanji(ink, { width: side, height: side }, preContext, ctl.signal));
        setFailed(false);
      } catch {
        if (!ctl.signal.aborted) setFailed(true);
      } finally {
        if (!ctl.signal.aborted) setBusy(false);
      }
    }, SETTLE_MS);
    return () => {
      clearTimeout(timer);
      ctl.abort();
    };
  }, [ink, preContext]);

  function pick(c: string) {
    onPick(c);
    setInk([]);
  }

  // Fixed slots, filled or not, so the panel keeps its shape between
  // characters instead of collapsing to an empty column. 10 = two rows of five
  // on a phone; from sm it is a 3×3 grid and the tenth hides.
  const slots = Array.from({ length: 10 }, (_, i) => candidates[i] ?? null);

  return (
    <div className="flex flex-col gap-3 rounded-card border border-line-soft bg-paper-dim/40 p-3 sm:flex-row">
      <div className="mx-auto w-full max-w-[240px] shrink-0 sm:mx-0 sm:w-[200px]">
        <div ref={wrap} className="relative">
          <WritingPad strokes={null} guideCount={0} ink={ink} onInk={setInk} showCount={false} />
          {ink.length === 0 && (
            <span className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center gap-1 px-6 text-center text-xs text-ink-mute">
              <PenLine size={18} className="opacity-60" />
              {T.handwriteHint}
            </span>
          )}
        </div>
      </div>

      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <p className="flex h-4 items-center gap-1.5 text-xs font-medium text-ink-soft">
          {failed ? <span className="text-red-700 dark:text-red-300">{T.handwriteFailed}</span> : T.handwritePick}
          {busy && <Loader2 size={12} className="animate-spin text-ink-mute" />}
        </p>
        <div lang="ja" className="grid grid-cols-5 gap-1.5 sm:grid-cols-3">
          {slots.map((c, i) =>
            c ? (
              <button
                key={`${i}-${c}`}
                type="button"
                onClick={() => pick(c)}
                title={c}
                className={`flex aspect-square items-center sm:aspect-auto sm:h-[50px] justify-center truncate rounded-control border px-0.5 font-medium text-ink transition hover:-translate-y-px hover:border-seal hover:shadow-sm ${
                  c.length > 1 ? "text-sm" : "text-2xl"
                } ${i === 0 ? "border-seal bg-seal-tint/60" : "border-line bg-surface"} ${i === 9 ? "sm:hidden" : ""}`}
              >
                {c}
              </button>
            ) : (
              <span
                key={i}
                aria-hidden
                className={`aspect-square rounded-control border border-dashed sm:aspect-auto sm:h-[50px] border-line-soft ${i === 9 ? "sm:hidden" : ""}`}
              />
            )
          )}
        </div>
        <div className="mt-auto flex gap-1.5 pt-1">
          <button
            type="button"
            disabled={!ink.length}
            onClick={() => setInk(ink.slice(0, -1))}
            className="hk-btn hk-btn-quiet flex-1 gap-1.5 px-2 py-1.5 text-xs disabled:opacity-40"
          >
            <Undo2 size={14} /> {T.writingUndo}
          </button>
          <button
            type="button"
            disabled={!ink.length}
            onClick={() => setInk([])}
            className="hk-btn hk-btn-quiet flex-1 gap-1.5 px-2 py-1.5 text-xs disabled:opacity-40"
          >
            <Trash2 size={14} /> {T.writingClear}
          </button>
        </div>
      </div>
    </div>
  );
}
