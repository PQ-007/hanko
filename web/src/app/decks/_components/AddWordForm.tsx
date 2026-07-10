"use client";

import { useRef, useState } from "react";
import type { Deck, Word } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";

export default function AddWordForm({
  deck,
  words,
  onAdded,
}: {
  deck: Deck;
  words: Word[];
  onAdded: () => void;
}) {
  const [term, setTerm] = useState("");
  const [reading, setReading] = useState("");
  const [meaning, setMeaning] = useState("");
  const [meaningMn, setMeaningMn] = useState("");
  const [busy, setBusy] = useState(false);
  const [looking, setLooking] = useState(false);
  // Term awaiting the user's "add anyway" confirmation (already in the deck).
  const [dupTerm, setDupTerm] = useState<string | null>(null);
  // The English value we last translated from (avoid re-translating on blur if
  // nothing changed, and never translate Mongolian edits in reverse).
  const lastEn = useRef("");

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
          translate(data.meaning); // auto-fill Mongolian from the looked-up English
        }
      }
    } finally {
      setLooking(false);
    }
  }

  // English -> Mongolian (overwrite). Only triggered by English changes.
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
      // leave blank; user can type it
    }
  }

  function onMeaningBlur() {
    const text = meaning.trim();
    if (text && text !== lastEn.current) translate(text);
  }

  function add() {
    const t = term.trim();
    if (!t) return;
    if (words.some((w) => w.term === t)) {
      setDupTerm(t);
      return;
    }
    doAdd();
  }

  async function doAdd() {
    const t = term.trim();
    if (!t) return;
    setBusy(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      await supabase.from("words").insert({
        deck_id: deck.id,
        user_id: user.id,
        term: t,
        reading: reading.trim() || null,
        meaning: meaning.trim() || null,
        meaning_mn: meaningMn.trim() || null,
      });
    }
    setTerm("");
    setReading("");
    setMeaning("");
    setMeaningMn("");
    setBusy(false);
    onAdded();
  }

  const inputCls = "rounded border border-gray-300 px-2 py-1.5 text-sm";

  return (
    <div className="rounded-lg border border-gray-200 bg-white p-4">
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-[1fr_1fr_1.5fr_1.5fr_auto]">
        <input value={term} onChange={(e) => setTerm(e.target.value)} onBlur={lookup} placeholder={T.term} className={inputCls} />
        <input value={reading} onChange={(e) => setReading(e.target.value)} placeholder={looking ? T.lookingUp : T.reading} className={inputCls} />
        <input value={meaning} onChange={(e) => setMeaning(e.target.value)} onBlur={onMeaningBlur} onKeyDown={(e) => e.key === "Enter" && onMeaningBlur()} placeholder={T.meaningEn} className={inputCls} />
        <input value={meaningMn} onChange={(e) => setMeaningMn(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} placeholder={T.mongolian} className={inputCls} />
        <button
          onClick={add}
          disabled={busy || !term.trim()}
          className="rounded bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-800 disabled:opacity-60 sm:col-span-2 lg:col-span-1"
        >
          {T.addWord}
        </button>
      </div>

      {dupTerm && (
        <div
          onClick={() => setDupTerm(null)}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-sm rounded-xl bg-white p-5 shadow-2xl"
          >
            <h3 className="text-base font-semibold text-gray-900">{T.duplicateWord}</h3>
            <p className="mt-2 text-sm text-gray-600">{T.duplicateWordConfirm(dupTerm)}</p>
            <div className="mt-5 flex justify-end gap-2">
              <button
                onClick={() => setDupTerm(null)}
                className="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
              >
                {T.cancel}
              </button>
              <button
                onClick={() => {
                  setDupTerm(null);
                  doAdd();
                }}
                className="rounded-md bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-800"
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
