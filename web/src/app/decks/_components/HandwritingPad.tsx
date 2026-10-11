"use client";

import { useEffect, useRef, useState } from "react";
import { Loader2, Trash2, Undo2 } from "@/ui/icons";
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

  return (
    <div className="grid grid-cols-1 gap-3 rounded-control border border-line-soft bg-paper-dim/50 p-2.5 sm:grid-cols-[200px_1fr]">
      <div className="mx-auto w-full max-w-[220px]">
        <div ref={wrap} className="relative">
          <WritingPad strokes={null} guideCount={0} ink={ink} onInk={setInk} showCount={false} />
          {ink.length === 0 && (
            <span className="pointer-events-none absolute inset-0 flex items-center justify-center px-4 text-center text-xs text-ink-mute">
              {T.handwriteHint}
            </span>
          )}
        </div>
        <div className="mt-2 flex gap-2">
          <button
            type="button"
            aria-label={T.writingUndo}
            title={T.writingUndo}
            disabled={!ink.length}
            onClick={() => setInk(ink.slice(0, -1))}
            className="hk-btn flex-1 px-2 py-1.5 disabled:opacity-40"
          >
            <Undo2 size={15} />
          </button>
          <button
            type="button"
            aria-label={T.writingClear}
            title={T.writingClear}
            disabled={!ink.length}
            onClick={() => setInk([])}
            className="hk-btn flex-1 px-2 py-1.5 disabled:opacity-40"
          >
            <Trash2 size={15} />
          </button>
        </div>
      </div>

      <div className="flex min-w-0 flex-col">
        <p className="mb-1.5 flex items-center gap-1 text-[11px] font-medium text-ink-mute">
          {T.handwritePick}
          {busy && <Loader2 size={11} className="animate-spin" />}
        </p>
        {failed ? (
          <p className="text-xs text-ink-soft">{T.handwriteFailed}</p>
        ) : (
          <div lang="ja" className="grid grid-cols-5 content-start gap-1.5 sm:grid-cols-3">
            {candidates.slice(0, 10).map((c, i) => (
              <button
                key={c}
                type="button"
                onClick={() => pick(c)}
                title={c}
                className={`flex h-11 items-center justify-center truncate rounded-control border px-1 font-medium text-ink transition hover:border-seal hover:bg-surface ${
                  c.length > 1 ? "text-base" : "text-2xl"
                } ${i === 0 ? "border-seal bg-surface" : "border-line bg-surface/60"}`}
              >
                {c}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
