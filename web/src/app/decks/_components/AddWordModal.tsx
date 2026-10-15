"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Check, Loader2, PenLine, Plus, Sparkle, X } from "@/ui/icons";
import type { Deck } from "@/lib/types";
import { askConfirm } from "@/ui/Dialog";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { useModalChrome } from "../_lib/useModal";
import { autofill, pickedMatch, type AutoKey, type Match, type WordFields } from "../_lib/addWord";
import { insertAt } from "../_lib/handwriting";
import { exampleRow } from "../_lib/exampleStore";
import ExampleSection, { useExample } from "./ExampleSection";
import HandwritingPad from "./HandwritingPad";

// Per-device conveniences, not state anything else reads.
const DECK_KEY = "hanko.quickAdd.deck";
const PAD_KEY = "hanko.addWord.pad";

// Long enough that a lookup isn't sent per keystroke (/api/lookup allows a
// burst of 30, then one a second), short enough to feel live.
const LOOKUP_DELAY_MS = 400;

const EMPTY: WordFields = { term: "", reading: "", meaning: "", meaningMn: "" };

function stored(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function store(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // A preference that doesn't survive a reload is a small loss.
  }
}

async function translateMn(text: string): Promise<string> {
  try {
    const res = await fetch(`/api/translate?text=${encodeURIComponent(text)}`);
    return res.ok ? ((await res.json()).mongolian ?? "") : "";
  } catch {
    return "";
  }
}

/**
 * Add words, from a deck or from the dashboard — one dialog for both.
 *
 * - The term is looked up on Jisho as it changes, and the matches are listed
 *   to pick from. The best one fills reading and meaning straight away, but
 *   only fields the user hasn't written themselves (rules in _lib/addWord.ts).
 *   Enter or Tab out of the term also swaps it for the dictionary form
 *   (担っています → 担う); the term is never rewritten mid-typing.
 * - A handwriting pad for kanji the user can read off a page but can't type.
 * - It stays open after each add: the point is a handful of words at once.
 * - An example sentence for the word (Tatoeba, with its translations),
 *   collapsed to one line under the details (ExampleSection).
 *
 * `deckId` fixes the deck (the deck view); without it there is a picker that
 * remembers the last deck. `onAdded` runs per word, for a caller whose list
 * can refresh behind the dialog; `onClose` reports how many were added, for
 * one that can only reload once, on dismissal (the stats dashboard swaps the
 * whole page for its loading scene, which would take the dialog with it).
 */
export default function AddWordModal({
  decks,
  deckId: fixedDeckId,
  onAdded,
  onClose,
}: {
  decks: Deck[];
  deckId?: string;
  onAdded?: () => void;
  onClose: (added: number) => void;
}) {
  const [deckId, setDeckId] = useState<string>(() => {
    if (fixedDeckId) return fixedDeckId;
    const remembered = stored(DECK_KEY);
    if (remembered && decks.some((d) => d.id === remembered)) return remembered;
    return decks[0]?.id ?? "";
  });
  const [form, setForm] = useState<{ f: WordFields; auto: Set<AutoKey> }>({ f: EMPTY, auto: new Set() });
  const f = form.f;
  const [matches, setMatches] = useState<{ term: string; list: Match[] } | null>(null);
  const [looking, setLooking] = useState(false);
  const [composing, setComposing] = useState(false);
  const [padOpen, setPadOpen] = useState(() => stored(PAD_KEY) === "1");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [added, setAdded] = useState<{ term: string; reading: string }[]>([]);
  // The word just saved, shown on the button for a moment as the confirmation.
  const [flash, setFlash] = useState<string | null>(null);
  // English whose translation came back empty, so the field stops saying
  // "translating" instead of spinning forever.
  const [mnFailedFor, setMnFailedFor] = useState<string | null>(null);
  const [isMac] = useState(() => /Mac|iP(hone|ad|od)/.test(navigator.platform || navigator.userAgent));
  // Caret in the term (null = at the end), kept here rather than read off the
  // input so the pad can insert without focusing it — focusing opens the
  // keyboard over the pad on a phone.
  const [caret, setCaret] = useState<{ start: number; end: number } | null>(null);

  const termRef = useRef<HTMLInputElement>(null);
  const cache = useRef(new Map<string, Match[]>());
  // The term a match was explicitly picked for: later lookups of that same
  // term mustn't swap the pick (生 read なま) back to the best match (せい).
  const pinnedFor = useRef<string | null>(null);
  // Enter/Tab came before the matches did: accept the best one on arrival.
  const pendingAccept = useRef<string | null>(null);
  // English the Mongolian was last translated from (blur re-translates only on change).
  const lastEn = useRef("");

  const example = useExample();

  const fixedDeck = fixedDeckId ? decks.find((d) => d.id === fixedDeckId) : undefined;
  const close = useCallback(() => onClose(added.length), [onClose, added.length]);
  useModalChrome(close);

  useEffect(() => {
    // On a touch screen with the pad open, focusing the term would put the
    // keyboard over the pad.
    const coarse = window.matchMedia?.("(pointer: coarse)").matches;
    if (!(coarse && padOpen)) termRef.current?.focus();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once, on open
  }, []);

  const setField = (k: keyof WordFields, v: string) =>
    setForm((p) => {
      const auto = new Set(p.auto);
      if (k !== "term") auto.delete(k);
      return { f: { ...p.f, [k]: v }, auto };
    });

  // Enter/Tab: the dictionary form replaces the term, the rest by the usual
  // rules — unless the term has changed since `m` was looked up for it.
  const accept = useCallback((m: Match, forTerm: string) => {
    setCaret(null);
    setForm((p) => {
      if (p.f.term.trim() !== forTerm) return p;
      const r = autofill({ ...p.f, term: m.word }, p.auto, m);
      return { f: r.fields, auto: r.auto };
    });
  }, []);

  // A click on a match: it wins outright, over anything typed.
  function choose(m: Match) {
    pinnedFor.current = m.word;
    example.suggest(m.word);
    setCaret(null);
    setForm((p) => {
      const keepMn = p.f.meaning === m.meaning;
      const auto = new Set<AutoKey>(["reading", "meaning"]);
      if (!keepMn || p.auto.has("meaningMn")) auto.add("meaningMn");
      return {
        f: { term: m.word, reading: m.reading, meaning: m.meaning, meaningMn: keepMn ? p.f.meaningMn : "" },
        auto,
      };
    });
  }

  const onMatches = useCallback(
    (term: string, list: Match[]) => {
      setMatches({ term, list });
      const best = list[0];
      // The sentence is for the dictionary form, and only for a real word.
      if (pinnedFor.current !== term) example.suggest(best?.word ?? "", term);
      if (!best) return;
      if (pendingAccept.current === term) {
        pendingAccept.current = null;
        if (pinnedFor.current !== term) accept(best, term);
        return;
      }
      if (pinnedFor.current === term) return;
      setForm((p) => {
        if (p.f.term.trim() !== term) return p;
        const r = autofill(p.f, p.auto, best);
        return { f: r.fields, auto: r.auto };
      });
    },
    [accept, example]
  );

  // Look the term up as it changes. Not mid-IME-composition: that's kana or
  // romaji on its way to being the word.
  const term = f.term.trim();
  useEffect(() => {
    if (!term || composing) return;
    const hit = cache.current.get(term);
    if (hit) {
      onMatches(term, hit);
      return;
    }
    const ctl = new AbortController();
    const timer = setTimeout(async () => {
      setLooking(true);
      try {
        const res = await fetch(`/api/lookup?term=${encodeURIComponent(term)}`, { signal: ctl.signal });
        const data = res.ok ? await res.json() : null;
        const list: Match[] = Array.isArray(data?.results) ? data.results : data?.word ? [data] : [];
        // Only a real answer is cached; a 429 or outage should be retried.
        if (res.ok) cache.current.set(term, list);
        onMatches(term, list);
      } catch {
        if (!ctl.signal.aborted) onMatches(term, []);
      } finally {
        if (!ctl.signal.aborted) setLooking(false);
      }
    }, LOOKUP_DELAY_MS);
    return () => {
      clearTimeout(timer);
      ctl.abort();
      setLooking(false);
    };
  }, [term, composing, onMatches]);

  // A machine-filled English meaning gets its Mongolian automatically, unless
  // the user has written their own. The answer is dropped if the English has
  // moved on in the meantime.
  const needMn = form.auto.has("meaning") && form.auto.has("meaningMn") && !f.meaningMn && !!f.meaning.trim();
  useEffect(() => {
    if (!needMn) return;
    const en = f.meaning;
    let live = true;
    translateMn(en).then((mn) => {
      if (!live) return;
      if (!mn) {
        setMnFailedFor(en);
        return;
      }
      lastEn.current = en.trim();
      setForm((p) =>
        p.f.meaning === en && p.auto.has("meaningMn") && !p.f.meaningMn
          ? { f: { ...p.f, meaningMn: mn }, auto: p.auto }
          : p
      );
    });
    return () => {
      live = false;
    };
  }, [needMn, f.meaning]);
  const translating = needMn && mnFailedFor !== f.meaning;

  useEffect(() => {
    if (!flash) return;
    const t = setTimeout(() => setFlash(null), 1400);
    return () => clearTimeout(t);
  }, [flash]);

  // Hand-edited English: translate on blur, as the edit dialog does.
  async function onMeaningBlur() {
    const en = f.meaning.trim();
    if (!en || en === lastEn.current) return;
    lastEn.current = en;
    const mn = await translateMn(en);
    if (mn)
      setForm((p) => {
        const auto = new Set(p.auto);
        auto.add("meaningMn");
        return { f: { ...p.f, meaningMn: mn }, auto };
      });
  }

  function acceptBest() {
    if (!term) return;
    if (matches?.term !== term) {
      pendingAccept.current = term;
      return;
    }
    const best = matches.list[0];
    if (best && pinnedFor.current !== term) accept(best, term);
  }

  function onTermKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key !== "Enter" || e.nativeEvent.isComposing || e.ctrlKey || e.metaKey) return;
    e.preventDefault();
    if (!term) return;
    // First Enter takes the dictionary form; once the term is it, Enter adds.
    if (matches?.term !== term) {
      pendingAccept.current = term;
      return;
    }
    const best = matches.list[0];
    if (best && pinnedFor.current !== term && best.word !== term) {
      accept(best, term);
      return;
    }
    add();
  }

  function onTermBlur(e: React.FocusEvent<HTMLInputElement>) {
    // Moving on to the next field or the Add button, yes. Not to the pad, its
    // toggle or a match: a candidate tapped mid-word would otherwise turn a
    // half-drawn 勉 into 勉強 just before 強 is appended to it. Nor to nothing
    // (null): that's the canvas, or another window.
    const to = e.relatedTarget as HTMLElement | null;
    if (to && !to.closest("[data-keep-term]")) acceptBest();
  }

  function insertDrawn(s: string) {
    const at = caret ?? { start: f.term.length, end: f.term.length };
    const r = insertAt(f.term, at.start, at.end, s);
    setCaret({ start: r.caret, end: r.caret });
    setField("term", r.text);
    const el = termRef.current;
    if (el && document.activeElement === el) requestAnimationFrame(() => el.setSelectionRange(r.caret, r.caret));
  }

  function resetForm() {
    setForm({ f: EMPTY, auto: new Set() });
    setMatches(null);
    pinnedFor.current = null;
    pendingAccept.current = null;
    setCaret(null);
    lastEn.current = "";
    example.clear();
  }

  function clearTerm() {
    resetForm();
    termRef.current?.focus();
  }

  function togglePad() {
    setPadOpen((o) => {
      store(PAD_KEY, o ? "0" : "1");
      return !o;
    });
  }

  function pickDeck(id: string) {
    setDeckId(id);
    store(DECK_KEY, id);
  }

  async function add() {
    const t = f.term.trim();
    if (!t || !deckId || busy) return;
    setBusy(true);
    setError(null);
    try {
      const { data: dup, error: dupErr } = await supabase
        .from("words")
        .select("id")
        .eq("deck_id", deckId)
        .eq("term", t)
        .eq("deleted", false)
        .limit(1);
      if (dupErr) throw dupErr;
      if (dup && dup.length > 0) {
        const ok = await askConfirm({
          title: T.duplicateWord,
          body: T.duplicateWordConfirm(t),
          confirmLabel: T.addAnyway,
        });
        if (!ok) return;
      }
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) throw new Error("");
      const meaning = f.meaning.trim();
      // Added before its translation came back: wait for it rather than save
      // a word with no Mongolian meaning.
      const meaningMn = f.meaningMn.trim() || (meaning ? await translateMn(meaning) : "");
      const ex = await example.settle(t);
      const { error: insErr } = await supabase.from("words").insert({
        deck_id: deckId,
        user_id: user.id,
        term: t,
        reading: f.reading.trim() || null,
        meaning: meaning || null,
        meaning_mn: meaningMn.trim() || null,
        // Only with a sentence, so adding still works on a database without
        // 0031.
        ...(ex.ja || ex.en || ex.mn ? exampleRow(ex) : {}),
      });
      if (insErr) throw insErr;
    } catch (e) {
      // Surfaced rather than swallowed: a failed insert that clears the fields
      // looks exactly like a successful one until the word never shows up.
      setError(e instanceof Error ? e.message : String((e as { message?: string })?.message ?? ""));
      return;
    } finally {
      setBusy(false);
    }

    setAdded((a) => [{ term: t, reading: f.reading.trim() }, ...a]);
    setFlash(t);
    resetForm();
    onAdded?.();
    if (!(padOpen && window.matchMedia?.("(pointer: coarse)").matches)) termRef.current?.focus();
  }


  const shownMatches = term && matches ? matches : null;
  const stale = shownMatches !== null && shownMatches.term !== term;
  const picked = shownMatches ? pickedMatch(f, shownMatches.list) : null;
  const canAdd = !!term && !busy && decks.length > 0;

  const inputCls =
    "hk-input w-full rounded-control border border-line bg-paper px-3 py-2.5 text-sm text-ink placeholder:text-ink-mute focus:border-seal focus:ring-2 focus:ring-seal-tint";

  return (
    <div
      onClick={close}
      className="hk-dialog-backdrop fixed inset-0 z-50 flex items-end justify-center bg-black/45 backdrop-blur-[2px] sm:items-center sm:p-4"
    >
      <div
        role="dialog"
        aria-modal
        aria-labelledby="hk-add-title"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
            e.preventDefault();
            add();
          }
        }}
        className="hk-dialog flex max-h-[92dvh] w-full max-w-lg flex-col overflow-hidden rounded-t-card border border-line bg-surface shadow-2xl sm:max-h-[min(880px,calc(100dvh-2rem))] sm:rounded-card"
      >
        {/* Header: title, the deck it goes into, what's been added so far. */}
        <div className="shrink-0 border-b border-line-soft px-5 pb-3 pt-4">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <h2 id="hk-add-title" className="text-[17px] font-semibold leading-snug text-ink">
                {T.quickAddTitle}
              </h2>
              {fixedDeck ? (
                <p className="mt-0.5 truncate text-xs text-ink-mute">{fixedDeck.name}</p>
              ) : (
                decks.length > 0 && (
                  <label className="mt-1 flex items-center gap-1.5 text-xs text-ink-mute">
                    {T.quickAddDeckLabel}
                    <select
                      value={deckId}
                      onChange={(e) => pickDeck(e.target.value)}
                      className="hk-input max-w-[14rem] truncate rounded-md border border-line bg-paper px-1.5 py-0.5 text-xs font-medium text-ink focus:border-seal"
                    >
                      {decks.map((d) => (
                        <option key={d.id} value={d.id}>
                          {d.name}
                        </option>
                      ))}
                    </select>
                  </label>
                )
              )}
            </div>
            <button
              onClick={close}
              title={T.closeLabel}
              aria-label={T.closeLabel}
              className="-mr-1.5 shrink-0 rounded-control p-1.5 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
            >
              <X size={18} />
            </button>
          </div>
          {added.length > 0 && (
            <div className="-mx-5 mt-2.5 flex items-center gap-1.5 overflow-x-auto px-5 [scrollbar-width:none]">
              <span className="flex shrink-0 items-center gap-1 text-xs font-semibold text-seal">
                <Check size={13} /> {added.length}
              </span>
              {added.map((w, i) => (
                <span
                  key={added.length - i}
                  lang="ja"
                  title={w.reading || undefined}
                  className={`shrink-0 rounded-full border px-2 py-0.5 text-xs ${
                    i === 0 ? "hk-chip-new border-seal/40 bg-seal-tint text-ink" : "border-line-soft bg-paper text-ink-soft"
                  }`}
                >
                  {w.term}
                </span>
              ))}
            </div>
          )}
        </div>

        {decks.length === 0 ? (
          <div className="p-5">
            <p className="text-sm text-ink-soft">{T.quickAddNoDecks}</p>
            <Link href="/decks" className="mt-4 hk-btn hk-btn-primary w-full px-4 py-2.5 text-sm">
              {T.decksNav}
            </Link>
          </div>
        ) : (
          <>
            <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-4">
              {/* The word itself — the one field that matters, so the big one. */}
              <div>
                <label htmlFor="hk-add-term" className="mb-1.5 block text-xs font-medium text-ink-soft">
                  {T.addTermLabel}
                </label>
                <div className="flex gap-2">
                  <div className="relative min-w-0 flex-1">
                    <input
                      id="hk-add-term"
                      ref={termRef}
                      lang="ja"
                      autoComplete="off"
                      spellCheck={false}
                      placeholder="勉強"
                      value={f.term}
                      onChange={(e) => {
                        setCaret({ start: e.target.selectionStart ?? 0, end: e.target.selectionEnd ?? 0 });
                        setField("term", e.target.value);
                      }}
                      onSelect={(e) => {
                        const el = e.currentTarget;
                        setCaret({ start: el.selectionStart ?? 0, end: el.selectionEnd ?? 0 });
                      }}
                      onCompositionStart={() => setComposing(true)}
                      onCompositionEnd={() => setComposing(false)}
                      onKeyDown={onTermKey}
                      onBlur={onTermBlur}
                      className="hk-input h-11 w-full rounded-control border border-line bg-paper pl-3 pr-16 text-lg font-medium text-ink placeholder:font-normal placeholder:text-ink-mute/50 focus:border-seal focus:ring-2 focus:ring-seal-tint"
                    />
                    <div data-keep-term className="absolute inset-y-0 right-1.5 flex items-center gap-0.5">
                      {looking && <Loader2 size={14} className="animate-spin text-ink-mute" />}
                      {f.term && (
                        <button
                          type="button"
                          onClick={clearTerm}
                          title={T.clearForm}
                          aria-label={T.clearForm}
                          className="rounded-full p-1 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
                        >
                          <X size={14} />
                        </button>
                      )}
                    </div>
                  </div>
                  <button
                    type="button"
                    data-keep-term
                    onClick={togglePad}
                    aria-pressed={padOpen}
                    title={T.handwrite}
                    aria-label={T.handwrite}
                    className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-control border transition ${
                      padOpen
                        ? "border-seal bg-seal-tint text-seal"
                        : "border-line bg-paper text-ink-soft hover:border-seal hover:text-seal"
                    }`}
                  >
                    <PenLine size={17} />
                  </button>
                </div>
              </div>

              {padOpen && (
                <div data-keep-term>
                  <HandwritingPad preContext={f.term.slice(0, caret?.start ?? f.term.length)} onPick={insertDrawn} />
                </div>
              )}

              {shownMatches && (
                <div data-keep-term className={`transition-opacity ${stale ? "opacity-50" : ""}`}>
                  <p className="mb-1.5 text-xs font-medium text-ink-soft">{T.addMatches}</p>
                  {shownMatches.list.length === 0 ? (
                    <p className="rounded-control border border-dashed border-line px-3 py-2.5 text-xs text-ink-mute">
                      {T.addMatchesNone}
                    </p>
                  ) : (
                    <ul className="max-h-48 space-y-1 overflow-y-auto">
                      {shownMatches.list.map((m) => {
                        const on = m === picked;
                        return (
                          <li key={`${m.word}|${m.reading}`}>
                            <button
                              type="button"
                              onClick={() => choose(m)}
                              aria-pressed={on}
                              className={`flex w-full items-center gap-3 rounded-control border px-3 py-2 text-left transition ${
                                on
                                  ? "border-seal bg-seal-tint/60"
                                  : "border-line-soft bg-paper hover:border-line hover:bg-paper-dim"
                              }`}
                            >
                              <span lang="ja" className="flex shrink-0 flex-col leading-tight">
                                <span className="text-base font-semibold text-ink">{m.word}</span>
                                {m.reading && m.reading !== m.word && (
                                  <span className="text-[11px] text-ink-mute">{m.reading}</span>
                                )}
                              </span>
                              <span className="line-clamp-2 min-w-0 flex-1 text-xs leading-snug text-ink-soft">
                                {m.meaning}
                              </span>
                              <span
                                className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full border ${
                                  on ? "border-seal bg-seal text-white" : "border-line"
                                }`}
                              >
                                {on && <Check size={12} />}
                              </span>
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                </div>
              )}

              {/* Details: filled from the dictionary, editable. */}
              <div className="space-y-3 rounded-card border border-line-soft bg-paper-dim/40 p-3">
                <Field id="hk-add-reading" label={T.reading} auto={form.auto.has("reading") && !!f.reading}>
                  <input
                    id="hk-add-reading"
                    lang="ja"
                    autoComplete="off"
                    value={f.reading}
                    onChange={(e) => setField("reading", e.target.value)}
                    className={inputCls}
                  />
                </Field>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <Field id="hk-add-meaning" label={T.meaningEn} auto={form.auto.has("meaning") && !!f.meaning}>
                    <input
                      id="hk-add-meaning"
                      autoComplete="off"
                      value={f.meaning}
                      onChange={(e) => setField("meaning", e.target.value)}
                      onBlur={onMeaningBlur}
                      onKeyDown={(e) => e.key === "Enter" && !e.ctrlKey && !e.metaKey && onMeaningBlur()}
                      className={inputCls}
                    />
                  </Field>
                  <Field
                    id="hk-add-mn"
                    label={T.mongolian}
                    auto={form.auto.has("meaningMn") && !!f.meaningMn}
                    busy={translating}
                  >
                    <input
                      id="hk-add-mn"
                      autoComplete="off"
                      value={f.meaningMn}
                      placeholder={translating ? T.lookingUp : undefined}
                      onChange={(e) => setField("meaningMn", e.target.value)}
                      onKeyDown={(e) => e.key === "Enter" && !e.ctrlKey && !e.metaKey && add()}
                      className={inputCls}
                    />
                  </Field>
                </div>
              </div>

              <ExampleSection store={example} />

              {error !== null && (
                <p role="alert" className="rounded-control border border-line bg-paper-dim px-3 py-2 text-xs text-red-700 dark:text-red-300">
                  {T.quickAddSaveFailed} {error}
                </p>
              )}
            </div>

            {/* Footer stays put while the body scrolls, so Add is always in reach. */}
            <div className="flex shrink-0 gap-2 border-t border-line-soft bg-surface px-5 pb-[max(0.875rem,env(safe-area-inset-bottom))] pt-3.5">
              <button onClick={close} className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm">
                {T.quickAddDone}
              </button>
              <button
                onClick={add}
                disabled={!canAdd}
                className="hk-btn hk-btn-primary flex-1 px-4 py-2.5 text-sm disabled:!bg-seal disabled:opacity-40"
              >
                {busy ? (
                  <Loader2 size={15} className="animate-spin" />
                ) : flash ? (
                  <>
                    <Check size={15} /> {T.addedFlash(flash)}
                  </>
                ) : (
                  <>
                    <Plus size={15} /> {T.addWord}
                    <kbd className="ml-1 rounded border border-white/30 px-1.5 py-px font-sans text-[10px] font-medium opacity-80 max-sm:hidden">
                      {isMac ? "⌘" : "Ctrl"} ↵
                    </kbd>
                  </>
                )}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

/** A labelled field that says when the dictionary filled it, or is filling it. */
function Field({
  id,
  label,
  auto,
  busy = false,
  children,
}: {
  id: string;
  label: string;
  auto: boolean;
  busy?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div>
      <div className="mb-1 flex items-center gap-1.5">
        <label htmlFor={id} className="text-xs font-medium text-ink-soft">
          {label}
        </label>
        {busy ? (
          <Loader2 size={11} className="animate-spin text-ink-mute" />
        ) : (
          auto && (
            <span title={T.autoFilledTitle} className="flex items-center gap-0.5 text-[10px] font-medium text-seal">
              <Sparkle size={10} /> {T.autoFilled}
            </span>
          )
        )}
      </div>
      {children}
    </div>
  );
}
