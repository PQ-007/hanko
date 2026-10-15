"use client";

import { useState, useSyncExternalStore } from "react";
import { ChevronDown, Loader2, Search } from "@/ui/icons";
import { findExample } from "@/lib/examples";
import { ExampleStore, type WordExample } from "../_lib/exampleStore";
import { T } from "../_lib/strings";

async function translateSentence(text: string): Promise<string> {
  try {
    const res = await fetch(`/api/translate?sentence=1&text=${encodeURIComponent(text)}`);
    return res.ok ? ((await res.json()).mongolian ?? "") : "";
  } catch {
    return "";
  }
}

/** One store per dialog, kept for its lifetime. */
export function useExample(initial?: WordExample | null): ExampleStore {
  const [store] = useState(
    () => new ExampleStore({ find: (t) => findExample(t), translate: translateSentence }, initial)
  );
  return store;
}

/**
 * The example sentence in the add and edit dialogs. Collapsed by default to
 * one line — the sentence, or why there isn't one — so a word with a sentence
 * costs the form a single row; a click opens the three fields. The mobile
 * side is ExampleSection in example_section.dart.
 */
export default function ExampleSection({
  store,
  onResearch,
}: {
  store: ExampleStore;
  /** Shown as a button when open (the edit dialog): fetch a new suggestion. */
  onResearch?: () => void;
}) {
  const s = useSyncExternalStore(store.subscribe, store.get, store.get);
  const [open, setOpen] = useState(false);
  const preview = s.ja.trim();
  const status = preview || (s.looking ? T.lookingUp : s.none ? T.exampleNone : T.exampleEmpty);
  const empty = !s.ja.trim() && !s.en.trim() && !s.mn.trim();

  const inputCls =
    "hk-input w-full rounded-control border border-line bg-paper px-3 py-2 text-sm text-ink placeholder:text-ink-mute focus:border-seal focus:ring-2 focus:ring-seal-tint";

  return (
    <div className="rounded-card border border-line-soft">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="flex w-full items-center gap-2 rounded-card px-3 py-2.5 text-left transition hover:bg-paper-dim/60"
      >
        <span className="shrink-0 text-xs font-medium text-ink-soft">{T.exampleTitle}</span>
        <span
          lang={preview ? "ja" : undefined}
          className={`min-w-0 flex-1 truncate text-sm ${preview ? "text-ink" : "text-ink-mute"}`}
        >
          {status}
        </span>
        {(s.looking || s.translating) && <Loader2 size={13} className="shrink-0 animate-spin text-ink-mute" />}
        <ChevronDown size={16} className={`shrink-0 text-ink-mute transition ${open ? "rotate-180" : ""}`} />
      </button>
      {open && (
        <div className="space-y-2.5 px-3 pb-3">
          <Labelled id="hk-ex-ja" label={T.exampleJa}>
            <textarea
              id="hk-ex-ja"
              lang="ja"
              rows={2}
              maxLength={300}
              value={s.ja}
              onChange={(e) => store.edit("ja", e.target.value)}
              className={`${inputCls} resize-y leading-snug`}
            />
          </Labelled>
          <Labelled id="hk-ex-en" label={T.exampleEn}>
            <textarea
              id="hk-ex-en"
              rows={2}
              maxLength={500}
              value={s.en}
              onChange={(e) => store.edit("en", e.target.value)}
              onBlur={() => store.englishLeft()}
              className={`${inputCls} resize-y leading-snug`}
            />
          </Labelled>
          <Labelled id="hk-ex-mn" label={T.exampleMn}>
            <textarea
              id="hk-ex-mn"
              rows={2}
              maxLength={500}
              value={s.mn}
              onChange={(e) => store.edit("mn", e.target.value)}
              className={`${inputCls} resize-y leading-snug`}
            />
          </Labelled>
          <div className="flex justify-end gap-1">
            {onResearch && (
              <button
                type="button"
                onClick={onResearch}
                disabled={s.looking}
                className="flex items-center gap-1 rounded-control px-2 py-1 text-xs font-medium text-ink-soft transition hover:bg-paper-dim disabled:opacity-50"
              >
                <Search size={13} /> {T.exampleSuggest}
              </button>
            )}
            {!empty && (
              <button
                type="button"
                onClick={() => store.clear()}
                className="rounded-control px-2 py-1 text-xs font-medium text-ink-soft transition hover:bg-paper-dim"
              >
                {T.exampleClear}
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function Labelled({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  return (
    <div>
      <label htmlFor={id} className="mb-1 block text-xs font-medium text-ink-soft">
        {label}
      </label>
      {children}
    </div>
  );
}
