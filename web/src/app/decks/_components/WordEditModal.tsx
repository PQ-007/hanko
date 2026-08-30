"use client";

import { useEffect, useRef, useState } from "react";
import { Languages, Search, X } from "lucide-react";
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
  const [looking, setLooking] = useState(false);
  const [translating, setTranslating] = useState(false);

  // The English value we last translated from — so blurring without editing
  // doesn't re-translate (and clobber a manual Mongolian edit).
  const lastEn = useRef((word.meaning ?? "").trim());

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

  // English -> Mongolian, overwriting the Mongolian field. Editing Mongolian
  // never triggers anything (no reverse translation).
  async function translate(text: string) {
    const t = text.trim();
    if (!t) return;
    lastEn.current = t;
    setTranslating(true);
    try {
      const res = await fetch(`/api/translate?text=${encodeURIComponent(t)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.mongolian) setMeaningMn(data.mongolian);
      }
    } catch {
      // leave as-is
    } finally {
      setTranslating(false);
    }
  }

  // Auto-translate when the English field loses focus AND its text changed.
  function onMeaningBlur() {
    const text = meaning.trim();
    if (text && text !== lastEn.current) translate(text);
  }

  // Re-search the current term on Jisho: normalize to the dictionary form and
  // overwrite reading + English, then re-translate the new English.
  async function relookup() {
    const t = term.trim();
    if (!t) return;
    setLooking(true);
    try {
      const res = await fetch(`/api/lookup?term=${encodeURIComponent(t)}`);
      if (res.ok) {
        const data = await res.json();
        if (data.word) setTerm(data.word);
        if (data.reading) setReading(data.reading);
        if (data.meaning) {
          setMeaning(data.meaning);
          translate(data.meaning);
        }
      }
    } catch {
      // leave fields as-is
    } finally {
      setLooking(false);
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

  const labelCls = "mb-1 block text-xs font-medium text-ink-soft";
  const inputCls =
    "w-full rounded-control border border-line px-3 py-2 text-sm focus:border-seal focus:outline-none focus:ring-2 focus:ring-seal-tint";
  const areaCls = `${inputCls} min-h-[72px] resize-y leading-snug`;

  return (
    <div
      onClick={onClose}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-md rounded-card bg-white p-5 shadow-2xl"
      >
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-base font-semibold text-ink">{T.editWord}</h3>
          <button
            onClick={onClose}
            className="rounded-control p-1 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
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

          {/* Re-search Jisho for the term (overwrites reading + English) */}
          <div className="flex justify-end">
            <button
              onClick={relookup}
              disabled={looking || !term.trim()}
              className="flex items-center gap-1 rounded-control px-2 py-1 text-xs font-medium text-ink-soft transition hover:bg-paper-dim disabled:opacity-50"
            >
              <Search size={13} /> {looking ? T.lookingUp : T.research}
            </button>
          </div>

          <div>
            <label className={labelCls}>{T.meaningEn}</label>
            <textarea
              value={meaning}
              onChange={(e) => setMeaning(e.target.value)}
              onBlur={onMeaningBlur}
              onKeyDown={(e) => {
                // Enter (without Shift) = "done" → translate now. Shift+Enter
                // still inserts a newline.
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  onMeaningBlur();
                }
              }}
              className={areaCls}
            />
          </div>
          <div>
            <div className="mb-1 flex items-center gap-2">
              <label className="text-xs font-medium text-ink-soft">{T.mongolian}</label>
              {translating && (
                <span className="flex items-center gap-1 text-xs text-ink-mute">
                  <Languages size={12} className="animate-pulse" /> {T.lookingUp}
                </span>
              )}
            </div>
            <textarea value={meaningMn} onChange={(e) => setMeaningMn(e.target.value)} className={areaCls} />
          </div>
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-control border border-line px-4 py-2 text-sm font-medium text-ink transition hover:bg-paper-dim"
          >
            {T.cancel}
          </button>
          <button
            onClick={save}
            disabled={saving || !term.trim()}
            className="hk-btn hk-btn-primary px-4 py-2 text-sm disabled:opacity-60"
          >
            {T.save}
          </button>
        </div>
      </div>
    </div>
  );
}
