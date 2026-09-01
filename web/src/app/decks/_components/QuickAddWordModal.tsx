"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Check, Plus, X } from "lucide-react";
import type { Deck } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { useModalChrome } from "../_lib/useModal";

// Remembering the deck matters more here than in the deck view, where the
// deck is implied by where you are. Per-device is the honest scope: it's a
// convenience, not state anything else reads.
const DECK_KEY = "hanko.quickAdd.deck";

function rememberedDeck(): string | null {
  try {
    return window.localStorage.getItem(DECK_KEY);
  } catch {
    return null;
  }
}

// Add a word without leaving the dashboard.
//
// Same four fields and the same Jisho lookup / EN→MN translation as
// AddWordForm, plus a deck picker — the one thing the in-deck form gets for
// free. It deliberately stays open after each add: the reason to want this at
// all is a handful of words at once, and a dialog that closes after one turns
// that into a handful of round trips through the dashboard.
//
// `onClose` carries how many words were added, so the caller reloads once, on
// dismissal, instead of per word. That isn't a micro-optimisation: the stats
// dashboard's reload swaps the whole page for its loading scene, which would
// unmount this dialog mid-typing.
export default function QuickAddWordModal({
  decks,
  onClose,
}: {
  decks: Deck[];
  onClose: (added: number) => void;
}) {
  const [deckId, setDeckId] = useState<string>(() => {
    const remembered = rememberedDeck();
    if (remembered && decks.some((d) => d.id === remembered)) return remembered;
    return decks[0]?.id ?? "";
  });
  const [term, setTerm] = useState("");
  const [reading, setReading] = useState("");
  const [meaning, setMeaning] = useState("");
  const [meaningMn, setMeaningMn] = useState("");
  const [busy, setBusy] = useState(false);
  const [looking, setLooking] = useState(false);
  const [added, setAdded] = useState(0);
  const [error, setError] = useState<string | null>(null);
  // Term awaiting an "add anyway" confirmation (already in the chosen deck).
  const [dupTerm, setDupTerm] = useState<string | null>(null);

  const termRef = useRef<HTMLInputElement>(null);
  // The English we last translated from, so blurring an unchanged field
  // doesn't overwrite a hand-typed Mongolian meaning.
  const lastEn = useRef("");

  // Escape must report the count too, or closing that way loses the reload.
  const close = useCallback(() => onClose(added), [onClose, added]);
  useModalChrome(close);

  useEffect(() => {
    termRef.current?.focus();
  }, []);

  function pickDeck(id: string) {
    setDeckId(id);
    try {
      window.localStorage.setItem(DECK_KEY, id);
    } catch {
      // A preference that doesn't survive a reload is a small loss.
    }
  }

  async function lookup() {
    const t = term.trim();
    if (!t) return;
    setLooking(true);
    try {
      const res = await fetch(`/api/lookup?term=${encodeURIComponent(t)}`);
      if (res.ok) {
        const data = await res.json();
        // Replace a conjugated term with its dictionary form (担っています → 担う).
        if (data.word && data.word !== t) setTerm(data.word);
        if (data.reading && !reading) setReading(data.reading);
        if (data.meaning && !meaning) {
          setMeaning(data.meaning);
          translate(data.meaning);
        }
      }
    } catch {
      // Lookup is a convenience; typing the fields by hand still works.
    } finally {
      setLooking(false);
    }
  }

  async function translate(text: string) {
    const t = text.trim();
    if (!t) return;
    lastEn.current = t;
    try {
      const res = await fetch(`/api/translate?text=${encodeURIComponent(t)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.mongolian) setMeaningMn(data.mongolian);
      }
    } catch {
      // leave blank; the user can type it
    }
  }

  function onMeaningBlur() {
    const text = meaning.trim();
    if (text && text !== lastEn.current) translate(text);
  }

  // The in-deck form checks for duplicates against the word list it already
  // holds. Nothing here holds that list, so ask the server — one round trip,
  // only at add time.
  async function add() {
    const t = term.trim();
    if (!t || !deckId) return;
    setBusy(true);
    setError(null);
    const { data, error: dupErr } = await supabase
      .from("words")
      .select("id")
      .eq("deck_id", deckId)
      .eq("term", t)
      .eq("deleted", false)
      .limit(1);
    setBusy(false);
    if (dupErr) {
      setError(dupErr.message);
      return;
    }
    if (data && data.length > 0) {
      setDupTerm(t);
      return;
    }
    doAdd();
  }

  async function doAdd() {
    const t = term.trim();
    if (!t || !deckId) return;
    setBusy(true);
    setError(null);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      setBusy(false);
      setError(T.quickAddSaveFailed);
      return;
    }
    const { error: insErr } = await supabase.from("words").insert({
      deck_id: deckId,
      user_id: user.id,
      term: t,
      reading: reading.trim() || null,
      meaning: meaning.trim() || null,
      meaning_mn: meaningMn.trim() || null,
    });
    setBusy(false);
    // Surfaced rather than swallowed. The in-deck form drops this error and
    // clears the fields anyway, so a failed insert looks exactly like a
    // successful one until you notice the word never appeared.
    if (insErr) {
      setError(insErr.message);
      return;
    }
    setAdded((n) => n + 1);
    setTerm("");
    setReading("");
    setMeaning("");
    setMeaningMn("");
    lastEn.current = "";
    termRef.current?.focus();
  }

  const inputCls =
    "w-full rounded-control border border-line bg-white px-3 py-2 text-sm focus:border-seal focus:outline-none focus:ring-2 focus:ring-seal-tint";

  return (
    <div
      onClick={close}
      role="dialog"
      aria-modal
      aria-label={T.quickAddTitle}
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/40 p-4"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="my-auto w-full max-w-md rounded-card bg-paper p-5 shadow-2xl"
      >
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-lg font-semibold text-ink">{T.quickAddTitle}</h2>
            {added > 0 && (
              <p className="mt-0.5 flex items-center gap-1 text-xs font-medium text-seal">
                <Check size={13} /> {T.quickAddedCount(added)}
              </p>
            )}
          </div>
          <button
            onClick={close}
            title={T.closeLabel}
            aria-label={T.closeLabel}
            className="shrink-0 rounded-control p-1 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
          >
            <X size={18} />
          </button>
        </div>

        {decks.length === 0 ? (
          <div className="mt-4">
            <p className="text-sm text-ink-soft">{T.quickAddNoDecks}</p>
            <Link
              href="/decks"
              className="mt-4 hk-btn hk-btn-primary w-full px-4 py-2.5 text-sm"
            >
              {T.decksNav}
            </Link>
          </div>
        ) : (
          <div className="mt-4 flex flex-col gap-2.5">
            <label className="flex flex-col gap-1">
              <span className="text-xs font-medium text-ink-mute">
                {T.quickAddDeckLabel}
              </span>
              <select
                value={deckId}
                onChange={(e) => pickDeck(e.target.value)}
                className={inputCls}
              >
                {decks.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.name}
                  </option>
                ))}
              </select>
            </label>

            <input
              ref={termRef}
              value={term}
              onChange={(e) => setTerm(e.target.value)}
              onBlur={lookup}
              onKeyDown={(e) => e.key === "Enter" && lookup()}
              placeholder={T.term}
              className={inputCls}
            />
            <input
              value={reading}
              onChange={(e) => setReading(e.target.value)}
              placeholder={looking ? T.lookingUp : T.reading}
              className={inputCls}
            />
            <input
              value={meaning}
              onChange={(e) => setMeaning(e.target.value)}
              onBlur={onMeaningBlur}
              onKeyDown={(e) => e.key === "Enter" && onMeaningBlur()}
              placeholder={T.meaningEn}
              className={inputCls}
            />
            <input
              value={meaningMn}
              onChange={(e) => setMeaningMn(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && add()}
              placeholder={T.mongolian}
              className={inputCls}
            />

            {error && (
              <p className="rounded-control border border-line bg-paper-dim px-3 py-2 text-xs text-ink">
                {T.quickAddSaveFailed} {error}
              </p>
            )}

            <div className="mt-1 flex gap-2">
              <button
                onClick={close}
                className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm"
              >
                {T.quickAddDone}
              </button>
              <button
                onClick={add}
                disabled={busy || !term.trim()}
                className="hk-btn hk-btn-primary flex-1 px-4 py-2.5 text-sm"
              >
                <Plus size={15} /> {T.addWord}
              </button>
            </div>
          </div>
        )}
      </div>

      {dupTerm && (
        <div
          onClick={(e) => {
            e.stopPropagation();
            setDupTerm(null);
          }}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-sm rounded-card bg-white p-5 shadow-2xl"
          >
            <h3 className="text-base font-semibold text-ink">{T.duplicateWord}</h3>
            <p className="mt-2 text-sm text-ink-soft">{T.duplicateWordConfirm(dupTerm)}</p>
            <div className="mt-5 flex justify-end gap-2">
              <button
                onClick={() => setDupTerm(null)}
                className="rounded-control border border-line px-4 py-2 text-sm font-medium text-ink transition hover:bg-paper-dim"
              >
                {T.cancel}
              </button>
              <button
                onClick={() => {
                  setDupTerm(null);
                  doAdd();
                }}
                className="hk-btn hk-btn-primary px-4 py-2 text-sm"
              >
                {T.addAnyway}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
