"use client";

import { useState, useSyncExternalStore } from "react";
import { Check, ChevronDown, Loader2, Pencil, Search, Trash2 } from "@/ui/icons";
import { findExample } from "@/lib/examples";
import { supabase } from "../_lib/db";
import { ExampleStore, exampleRow, type WordExample } from "../_lib/exampleStore";
import { T } from "../_lib/strings";
import RubySentence from "./RubySentence";

const translated = new Map<string, Promise<string>>();

/**
 * English → Mongolian, kept whole. Shared per sentence: the form and a save
 * finishing the same sentence ask once. A failure ("") is forgotten so it's
 * retried.
 */
export function translateSentence(text: string): Promise<string> {
  const t = text.trim();
  if (!t) return Promise.resolve("");
  const hit = translated.get(t);
  if (hit) return hit;
  const p = (async () => {
    try {
      const res = await fetch(`/api/translate?sentence=1&text=${encodeURIComponent(t)}`);
      return res.ok ? (((await res.json()).mongolian as string) ?? "") : "";
    } catch {
      return "";
    }
  })();
  translated.set(t, p);
  p.then((out) => {
    if (!out) translated.delete(t);
  });
  return p;
}

/**
 * A sentence that was still on its way when the word was saved
 * (ExampleStore.take) lands on it once it arrives — and only if the word
 * still has none. Best effort: a failure leaves the word without one, which
 * the edit dialog or the deck's fill can make up later.
 */
export function attachExampleLater(wordId: string, later: Promise<WordExample | null> | null) {
  if (!later) return;
  later
    .then(async (e) => {
      if (!e || !(e.ja || e.en || e.mn)) return;
      await supabase.from("words").update(exampleRow(e)).eq("id", wordId).is("example_ja", null);
    })
    .catch(() => {});
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
 * the title and the whole sentence (or why there isn't one), never cut off,
 * so it can be checked without opening. Opened, it reads first: the sentence with
 * furigana and the word picked out, then its translations; editing is a
 * mode you switch into, each field tagged with its language. The mobile side
 * is ExampleSection in example_section.dart.
 */
export default function ExampleSection({
  store,
  term,
  onResearch,
}: {
  store: ExampleStore;
  /** The word being added or edited, picked out in the sentence. */
  term: string;
  /** Fetch a fresh suggestion (Tatoeba), over whatever is there. */
  onResearch?: () => void;
}) {
  const s = useSyncExternalStore(store.subscribe, store.get, store.get);
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState(false);
  const preview = s.ja.trim();
  const empty = !s.ja.trim() && !s.en.trim() && !s.mn.trim();
  // No "searching…" while closed: the field is optional, so nobody needs to
  // watch it fill — the sentence just appears.
  const status = s.looking ? "" : s.none ? T.exampleNone : T.exampleEmpty;
  const furigana = store.value.furigana;
  const busy = s.looking || s.translating;
  // Nothing to read yet: open straight into the fields.
  const showFields = editing || (empty && !s.looking);

  const field =
    "hk-input w-full resize-none rounded-control border border-line bg-paper py-2 pl-3 pr-12 text-sm leading-snug text-ink placeholder:text-ink-mute focus:border-seal focus:ring-2 focus:ring-seal-tint";
  const iconBtn =
    "rounded-control p-1.5 text-ink-mute transition hover:bg-paper-dim hover:text-ink disabled:opacity-40";

  return (
    <div className={`rounded-card border transition-colors ${open ? "border-line bg-paper-dim/30" : "border-line-soft"}`}>
      <div className="flex items-start gap-1 pr-1.5">
        <button
          type="button"
          onClick={() => setOpen((o) => !o)}
          aria-expanded={open}
          className="flex min-w-0 flex-1 flex-col gap-1 rounded-card py-2.5 pl-3 text-left"
        >
          <span className="flex items-center gap-2">
            <ChevronDown size={15} className={`shrink-0 text-ink-mute transition ${open ? "" : "-rotate-90"}`} />
            <span className="text-xs font-medium text-ink-soft">{T.exampleTitle}</span>
            {/* No sentence yet: the reason sits on the title line. */}
            {!open && !preview && status && <span className="text-xs text-ink-mute">· {status}</span>}
          </span>
          {/* Closed, the whole sentence — never cut off. Open, it's right below. */}
          {!open && preview && (
            <span key={preview} lang="ja" className="animate-[fadeUp_240ms_ease-out] pl-[23px] text-sm leading-snug text-ink">
              {preview}
            </span>
          )}
        </button>
        {open && (
          <div className="flex shrink-0 items-center gap-0.5 pt-1.5">
            {busy && <Loader2 size={14} className="mx-1 animate-spin text-ink-mute" />}
            {onResearch && (
              <button
                type="button"
                onClick={() => {
                  setEditing(false);
                  onResearch();
                }}
                disabled={s.looking}
                title={T.exampleSuggest}
                aria-label={T.exampleSuggest}
                className={iconBtn}
              >
                <Search size={15} />
              </button>
            )}
            {!empty && (
              <button
                type="button"
                onClick={() => setEditing((e) => !e)}
                aria-pressed={editing}
                title={editing ? T.exampleDone : T.exampleEdit}
                aria-label={editing ? T.exampleDone : T.exampleEdit}
                className={`${iconBtn} ${editing ? "bg-seal-tint text-seal hover:text-seal" : ""}`}
              >
                {editing ? <Check size={15} /> : <Pencil size={15} />}
              </button>
            )}
            {!empty && (
              <button
                type="button"
                onClick={() => {
                  store.clear();
                  setEditing(false);
                }}
                title={T.exampleClear}
                aria-label={T.exampleClear}
                className={`${iconBtn} hover:text-red-700 dark:hover:text-red-300`}
              >
                <Trash2 size={15} />
              </button>
            )}
          </div>
        )}
      </div>

      {open && (
        <div className="px-3 pb-3">
          {s.looking && empty ? (
            // Placeholder lines, the shape of what's coming.
            <div className="space-y-2 py-1" aria-hidden>
              <div className="h-4 w-4/5 animate-pulse rounded bg-line-soft" />
              <div className="h-3 w-3/5 animate-pulse rounded bg-line-soft" />
            </div>
          ) : showFields ? (
            <div className="space-y-2">
              {empty && s.none && <p className="text-xs text-ink-mute">{T.exampleNone}</p>}
              <Tagged tag="日本語">
                <textarea
                  lang="ja"
                  rows={2}
                  maxLength={300}
                  value={s.ja}
                  placeholder={T.exampleJa}
                  aria-label={T.exampleJa}
                  onChange={(e) => store.edit("ja", e.target.value)}
                  className={`${field} text-[15px]`}
                />
              </Tagged>
              <Tagged tag="EN">
                <textarea
                  rows={2}
                  maxLength={500}
                  value={s.en}
                  placeholder={T.exampleEn}
                  aria-label={T.exampleEn}
                  onChange={(e) => store.edit("en", e.target.value)}
                  onBlur={() => store.englishLeft()}
                  className={field}
                />
              </Tagged>
              <Tagged tag="MN">
                <textarea
                  rows={2}
                  maxLength={500}
                  value={s.mn}
                  placeholder={s.translating ? T.lookingUp : T.exampleMn}
                  aria-label={T.exampleMn}
                  onChange={(e) => store.edit("mn", e.target.value)}
                  className={field}
                />
              </Tagged>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setEditing(true)}
              title={T.exampleEdit}
              className="block w-full rounded-control text-left"
            >
              <RubySentence
                ja={s.ja}
                furigana={furigana}
                term={term}
                className="block text-[17px] leading-[2.1] text-ink"
              />
              {s.mn && <span className="mt-1 block text-sm leading-snug text-ink-soft">{s.mn}</span>}
              {s.en && <span className="mt-0.5 block text-xs leading-snug text-ink-mute">{s.en}</span>}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

/** A field with its language in the corner, so a filled one still says what it is. */
function Tagged({ tag, children }: { tag: string; children: React.ReactNode }) {
  return (
    <div className="relative">
      {children}
      <span className="pointer-events-none absolute right-2.5 top-2 text-[10px] font-medium text-ink-mute/80">{tag}</span>
    </div>
  );
}
