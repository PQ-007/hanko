"use client";

import { useEffect, useState } from "react";
import { X } from "lucide-react";
import type { Word } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";

// Modal dialog for editing a word.
export default function WordEditModal({
  word,
  onClose,
  onSaved,
}: {
  word: Word;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [term, setTerm] = useState(word.term);
  const [reading, setReading] = useState(word.reading ?? "");
  const [meaning, setMeaning] = useState(word.meaning ?? "");
  const [meaningMn, setMeaningMn] = useState(word.meaning_mn ?? "");
  const [saving, setSaving] = useState(false);

  // Close on Escape, and lock background scroll while open.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [onClose]);

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
      // leave as-is
    }
  }

  async function save() {
    if (!term.trim()) return;
    setSaving(true);
    await supabase
      .from("words")
      .update({
        term: term.trim(),
        reading: reading.trim() || null,
        meaning: meaning.trim() || null,
        meaning_mn: meaningMn.trim() || null,
      })
      .eq("id", word.id);
    setSaving(false);
    onSaved();
  }

  const labelCls = "mb-1 block text-xs font-medium text-gray-500";
  const inputCls =
    "w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-200";
  const areaCls = `${inputCls} min-h-[72px] resize-y leading-snug`;

  return (
    <div
      onClick={onClose}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-md rounded-xl bg-white p-5 shadow-2xl"
      >
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-base font-semibold text-gray-900">{T.editWord}</h3>
          <button
            onClick={onClose}
            className="rounded p-1 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700"
          >
            <X size={18} />
          </button>
        </div>

        <div className="space-y-3">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <label className={labelCls}>{T.term}</label>
              <input autoFocus value={term} onChange={(e) => setTerm(e.target.value)} className={inputCls} />
            </div>
            <div>
              <label className={labelCls}>{T.reading}</label>
              <input value={reading} onChange={(e) => setReading(e.target.value)} className={inputCls} />
            </div>
          </div>
          <div>
            <label className={labelCls}>{T.meaningEn}</label>
            <textarea value={meaning} onChange={(e) => setMeaning(e.target.value)} onBlur={translateMn} className={areaCls} />
          </div>
          <div>
            <label className={labelCls}>{T.mongolian}</label>
            <textarea value={meaningMn} onChange={(e) => setMeaningMn(e.target.value)} className={areaCls} />
          </div>
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
          >
            {T.cancel}
          </button>
          <button
            onClick={save}
            disabled={saving || !term.trim()}
            className="rounded-md bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-800 disabled:opacity-60"
          >
            {T.save}
          </button>
        </div>
      </div>
    </div>
  );
}
