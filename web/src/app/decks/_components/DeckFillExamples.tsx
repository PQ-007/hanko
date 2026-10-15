"use client";

import { useEffect, useRef, useState } from "react";
import { X } from "@/ui/icons";
import { findExample } from "@/lib/examples";
import { supabase } from "../_lib/db";
import { exampleRow } from "../_lib/exampleStore";
import { fillExamples, type FillResult } from "../_lib/fillExamples";
import { T } from "../_lib/strings";
import { useModalChrome } from "../_lib/useModal";
import { translateSentence } from "./ExampleSection";

type Phase =
  | { kind: "loading" }
  | { kind: "failed" }
  | { kind: "ready"; words: { id: string; term: string }[] }
  | { kind: "running"; done: number; total: number }
  | { kind: "finished"; result: FillResult };

/**
 * "Add example sentences" for a deck (the ⋯ menu): one Tatoeba sentence for
 * every word that has none, with a count first, progress, and a way to stop.
 * Rules in _lib/fillExamples.ts; the mobile side is fill_examples.dart.
 */
export default function DeckFillExamples({
  deckId,
  onClose,
}: {
  deckId: string;
  /** `changed`: some word got a sentence, so the list should reload. */
  onClose: (changed: boolean) => void;
}) {
  const [phase, setPhase] = useState<Phase>({ kind: "loading" });
  const cancelled = useRef(false);
  const added = useRef(0);
  const close = () => {
    cancelled.current = true;
    onClose(added.current > 0);
  };
  useModalChrome(close);

  useEffect(() => {
    supabase
      .from("words")
      .select("id, term")
      .eq("deck_id", deckId)
      .eq("deleted", false)
      .is("example_ja", null)
      .order("date_added")
      .then(({ data, error }) => setPhase(error ? { kind: "failed" } : { kind: "ready", words: data ?? [] }));
  }, [deckId]);

  async function start(words: { id: string; term: string }[]) {
    setPhase({ kind: "running", done: 0, total: words.length });
    const result = await fillExamples(words, {
      find: (t) => findExample(t),
      translate: translateSentence,
      // Only a word still without a sentence: one typed meanwhile wins.
      save: async (id, e) => {
        const { data, error } = await supabase
          .from("words")
          .update(exampleRow(e))
          .eq("id", id)
          .is("example_ja", null)
          .select("id");
        if (error) throw error;
        const ok = (data?.length ?? 0) > 0;
        if (ok) added.current++;
        return ok;
      },
      onProgress: (done, total) => setPhase({ kind: "running", done, total }),
      cancelled: () => cancelled.current,
    });
    if (!cancelled.current) setPhase({ kind: "finished", result });
  }

  const running = phase.kind === "running";
  return (
    <div onClick={close} className="hk-dialog-backdrop fixed inset-0 z-50 flex items-center justify-center bg-black/45 p-4">
      <div
        role="dialog"
        aria-modal
        aria-labelledby="hk-fill-title"
        onClick={(e) => e.stopPropagation()}
        className="hk-dialog w-full max-w-sm rounded-card border border-line bg-surface p-5 shadow-2xl"
      >
        <div className="mb-3 flex items-center justify-between">
          <h3 id="hk-fill-title" className="text-base font-semibold text-ink">
            {T.fillExamples}
          </h3>
          <button onClick={close} aria-label={T.closeLabel} className="rounded-control p-1 text-ink-mute hover:bg-paper-dim hover:text-ink">
            <X size={18} />
          </button>
        </div>

        {phase.kind === "loading" && <p className="text-sm text-ink-mute">{T.lookingUp}</p>}
        {phase.kind === "failed" && <p className="text-sm text-ink-soft">{T.fillExamplesFailed}</p>}
        {phase.kind === "ready" && (
          <p className="text-sm leading-relaxed text-ink-soft">
            {phase.words.length ? T.fillExamplesBody(phase.words.length) : T.fillExamplesAllDone}
          </p>
        )}
        {running && (
          <div>
            <p className="text-sm text-ink-soft">{T.fillExamplesProgress(phase.done, phase.total)}</p>
            <div className="mt-2 h-2 overflow-hidden rounded-full bg-line-soft">
              <div
                className="h-full bg-seal transition-all"
                style={{ width: `${phase.total ? (phase.done / phase.total) * 100 : 0}%` }}
              />
            </div>
          </div>
        )}
        {phase.kind === "finished" && (
          <p className="text-sm text-ink">{T.fillExamplesResult(phase.result.added, phase.result.missing)}</p>
        )}

        <div className="mt-5 flex justify-end gap-2">
          <button onClick={close} className="hk-btn hk-btn-quiet px-4 py-2 text-sm">
            {phase.kind === "finished" || phase.kind === "failed" ? T.closeLabel : T.cancel}
          </button>
          {phase.kind === "ready" && phase.words.length > 0 && (
            <button onClick={() => start(phase.words)} className="hk-btn hk-btn-primary px-4 py-2 text-sm">
              {T.fillExamplesStart}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
