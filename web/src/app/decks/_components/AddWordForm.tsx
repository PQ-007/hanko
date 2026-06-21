"use client";

import { useState } from "react";
import type { Deck } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";

export default function AddWordForm({
  deck,
  onAdded,
}: {
  deck: Deck;
  onAdded: () => void;
}) {
  const [term, setTerm] = useState("");
  const [reading, setReading] = useState("");
  const [meaning, setMeaning] = useState("");
  const [meaningMn, setMeaningMn] = useState("");
  const [busy, setBusy] = useState(false);
  const [looking, setLooking] = useState(false);

  async function lookup() {
    const t = term.trim();
    if (!t) return;
    setLooking(true);
    try {
      const res = await fetch(`/api/lookup?term=${encodeURIComponent(t)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.reading && !reading) setReading(data.reading);
        if (data.meaning && !meaning) setMeaning(data.meaning);
        if (data.meaning_mn && !meaningMn) setMeaningMn(data.meaning_mn);
      }
    } finally {
      setLooking(false);
    }
  }

  async function translateMn() {
    const text = meaning.trim();
    if (!text || meaningMn.trim()) return;
    try {
      const res = await fetch(`/api/translate?text=${encodeURIComponent(text)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.mongolian) setMeaningMn(data.mongolian);
      }
    } catch {
      // leave blank; user can type it
    }
  }

  async function add() {
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
        <input value={meaning} onChange={(e) => setMeaning(e.target.value)} onBlur={translateMn} placeholder={T.meaningEn} className={inputCls} />
        <input value={meaningMn} onChange={(e) => setMeaningMn(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} placeholder={T.mongolian} className={inputCls} />
        <button
          onClick={add}
          disabled={busy || !term.trim()}
          className="rounded bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-800 disabled:opacity-60 sm:col-span-2 lg:col-span-1"
        >
          {T.addWord}
        </button>
      </div>
    </div>
  );
}
