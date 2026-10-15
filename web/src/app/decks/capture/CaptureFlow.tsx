"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Check, Image as ImageIcon, Loader2, Plus } from "@/ui/icons";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { suggestWords } from "../_lib/segment";
import { resolveCapture, type CaptureItem } from "../_lib/captureLookup";

/** Shared with the add-word dialog and mobile: one remembered "last deck". */
const DECK_KEY = "hanko.quickAdd.deck";

type Stage =
  | { kind: "pick" }
  | { kind: "reading"; pct: number }
  | { kind: "select" }
  | { kind: "resolving"; done: number; total: number }
  | { kind: "review" }
  | { kind: "saved"; n: number };

async function lookup(term: string) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(`/api/lookup?term=${encodeURIComponent(term)}`);
    // /api/lookup allows a burst of 30, then one a second: a big page waits its turn.
    if (res.status === 429) {
      await new Promise((r) => setTimeout(r, 1100 * (Number(res.headers.get("Retry-After")) || 1)));
      continue;
    }
    if (!res.ok) return null;
    const d = await res.json();
    return d?.word ? { word: d.word as string, reading: (d.reading as string) ?? "", meaning: (d.meaning as string) ?? "" } : null;
  }
  return null;
}

async function translate(text: string) {
  const res = await fetch(`/api/translate?text=${encodeURIComponent(text)}`);
  return res.ok ? (((await res.json()).mongolian as string) ?? "") : "";
}

/**
 * Words from a photo — mobile's features/capture on the web: a photo or
 * screenshot → Japanese text recognised in the browser (_lib/ocr.ts) →
 * suggested words (_lib/segment.ts), plus any text selected by hand → looked
 * up on Jisho with their Mongolian → checked, edited → saved to a deck in one
 * insert (so they show as one batch in the deck, with "undo all").
 *
 * Mobile's crop and draw-to-select on the photo aren't here: the recognised
 * text is shown as text instead, and selecting from it does the same job.
 */
export default function CaptureFlow() {
  const params = useSearchParams();
  const [stage, setStage] = useState<Stage>({ kind: "pick" });
  const [photo, setPhoto] = useState<string | null>(null);
  const [text, setText] = useState("");
  const [chosen, setChosen] = useState<string[]>([]);
  const [items, setItems] = useState<(CaptureItem & { on: boolean; inDeck: boolean })[]>([]);
  const [decks, setDecks] = useState<{ id: string; name: string }[]>([]);
  const [deckId, setDeckId] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const textArea = useRef<HTMLTextAreaElement>(null);
  const camera = useRef<HTMLInputElement>(null);
  const gallery = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase
      .from("decks")
      .select("id, name")
      .eq("deleted", false)
      .order("name")
      .then(({ data }) => {
        const list = (data as { id: string; name: string }[]) ?? [];
        setDecks(list);
        let remembered: string | null = null;
        try {
          remembered = localStorage.getItem(DECK_KEY);
        } catch {}
        const want = params.get("deck") ?? remembered;
        setDeckId(list.some((d) => d.id === want) ? want! : (list[0]?.id ?? ""));
      });
  }, [params]);

  useEffect(() => () => void (photo && URL.revokeObjectURL(photo)), [photo]);

  const suggestions = useMemo(() => suggestWords(text.split("\n")), [text]);

  async function read(file: File | undefined) {
    if (!file) return;
    setError(null);
    setPhoto(URL.createObjectURL(file));
    setStage({ kind: "reading", pct: 0 });
    try {
      const { recognizeJapanese } = await import("../_lib/ocr");
      const r = await recognizeJapanese(file, (p) => setStage({ kind: "reading", pct: p * 100 }));
      const t = r.lines.join("\n");
      if (!suggestWords(r.lines).length && !t) {
        setError(T.captureNothingFound);
        setStage({ kind: "pick" });
        return;
      }
      setText(t);
      setChosen(suggestWords(r.lines));
      setStage({ kind: "select" });
    } catch {
      setError(T.captureFailed);
      setStage({ kind: "pick" });
    }
  }

  function toggle(w: string) {
    setChosen((c) => (c.includes(w) ? c.filter((x) => x !== w) : [...c, w]));
  }

  function addSelection() {
    const el = textArea.current;
    if (!el) return;
    const sel = el.value.slice(el.selectionStart, el.selectionEnd).replace(/\s+/g, "");
    if (sel && !chosen.includes(sel)) setChosen((c) => [...c, sel]);
  }

  async function resolve() {
    setStage({ kind: "resolving", done: 0, total: chosen.length });
    const found = await resolveCapture(chosen, {
      lookup,
      translate,
      onProgress: (done, total) => setStage({ kind: "resolving", done, total }),
    });
    const { data: existing } = deckId
      ? await supabase.from("words").select("term").eq("deck_id", deckId).eq("deleted", false).in("term", found.map((f) => f.term))
      : { data: [] };
    const inDeck = new Set((existing ?? []).map((r: { term: string }) => r.term));
    setItems(found.map((f) => ({ ...f, on: !inDeck.has(f.term), inDeck: inDeck.has(f.term) })));
    setStage({ kind: "review" });
  }

  function edit(i: number, patch: Partial<CaptureItem & { on: boolean }>) {
    setItems((its) => its.map((it, k) => (k === i ? { ...it, ...patch } : it)));
  }

  async function save() {
    const picked = items.filter((it) => it.on && it.term.trim());
    if (!picked.length || !deckId) return;
    setError(null);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    // One insert: every row gets the same date_added, which is what makes the
    // deck show them as one batch, with "undo all" (CLAUDE.md, capture).
    const { error: insErr } = await supabase.from("words").insert(
      picked.map((it) => ({
        deck_id: deckId,
        user_id: user.id,
        term: it.term.trim(),
        reading: it.reading.trim() || null,
        meaning: it.meaning.trim() || null,
        meaning_mn: it.meaningMn.trim() || null,
      }))
    );
    if (insErr) {
      setError(T.captureSaveFailed);
      return;
    }
    try {
      localStorage.setItem(DECK_KEY, deckId);
    } catch {}
    setStage({ kind: "saved", n: picked.length });
  }

  function restart() {
    setPhoto(null);
    setText("");
    setChosen([]);
    setItems([]);
    setError(null);
    setStage({ kind: "pick" });
  }

  const input = "hk-input w-full rounded-control border border-line bg-paper px-2.5 py-1.5 text-sm text-ink";
  const chip = (on: boolean) =>
    `rounded-full border px-3 py-1 text-sm transition ${on ? "border-seal bg-seal-tint text-ink" : "border-line text-ink-mute line-through"}`;

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-4 px-4 py-6 sm:py-10">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold tracking-tight text-ink">
          <ImageIcon size={22} /> {T.captureTitle}
        </h1>
        <p className="mt-1 text-sm text-ink-soft">{T.captureIntro}</p>
      </div>

      {/* Hidden pickers: `capture` opens the camera on a phone; without it, the photo library (and screenshots). */}
      <input ref={camera} type="file" accept="image/*" capture="environment" hidden onChange={(e) => read(e.target.files?.[0])} />
      <input ref={gallery} type="file" accept="image/*" hidden onChange={(e) => read(e.target.files?.[0])} />

      {stage.kind === "pick" && (
        <div className="flex flex-wrap gap-2">
          <button onClick={() => camera.current?.click()} className="hk-btn hk-btn-primary px-4 py-2.5 text-sm">
            {T.captureTakePhoto}
          </button>
          <button onClick={() => gallery.current?.click()} className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm">
            {T.captureFromGallery}
          </button>
        </div>
      )}

      {photo && stage.kind !== "pick" && stage.kind !== "saved" && (
        // eslint-disable-next-line @next/next/no-img-element -- a local object URL, not a remote image
        <img src={photo} alt="" className="max-h-56 w-full rounded-card border border-line-soft object-contain" />
      )}

      {stage.kind === "reading" && (
        <div>
          <p className="flex items-center gap-2 text-sm text-ink-soft">
            <Loader2 size={14} className="animate-spin" /> {T.captureReading}
          </p>
          <div className="mt-2 h-2 overflow-hidden rounded-full bg-line-soft">
            <div className="h-full bg-seal transition-all" style={{ width: `${stage.pct}%` }} />
          </div>
          <p className="mt-1 text-xs text-ink-mute">{T.captureFirstTime}</p>
        </div>
      )}

      {stage.kind === "select" && (
        <>
          <section className="hk-card p-4">
            <h2 className="text-sm font-semibold text-ink">{T.captureSuggestions}</h2>
            <p className="mb-3 text-xs text-ink-mute">{T.captureSuggestionsHint}</p>
            <div className="flex flex-wrap gap-1.5" lang="ja">
              {[...new Set([...suggestions, ...chosen])].map((w) => (
                <button key={w} onClick={() => toggle(w)} aria-pressed={chosen.includes(w)} className={chip(chosen.includes(w))}>
                  {w}
                </button>
              ))}
            </div>
          </section>
          <section className="hk-card p-4">
            <h2 className="text-sm font-semibold text-ink">{T.captureText}</h2>
            <p className="mb-2 text-xs text-ink-mute">{T.captureTextHint}</p>
            <textarea
              ref={textArea}
              lang="ja"
              value={text}
              onChange={(e) => setText(e.target.value)}
              rows={Math.min(10, Math.max(3, text.split("\n").length))}
              className={`${input} text-base leading-relaxed`}
            />
            <button onClick={addSelection} className="hk-btn hk-btn-quiet mt-2 px-3 py-1.5 text-xs">
              <Plus size={13} /> {T.captureAddSelection}
            </button>
          </section>
          <div className="flex flex-wrap gap-2">
            <button onClick={resolve} disabled={!chosen.length} className="hk-btn hk-btn-primary px-4 py-2.5 text-sm disabled:opacity-50">
              {T.captureNext(chosen.length)}
            </button>
            <button onClick={restart} className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm">
              {T.captureAnotherPhoto}
            </button>
          </div>
        </>
      )}

      {stage.kind === "resolving" && (
        <p className="flex items-center gap-2 text-sm text-ink-soft">
          <Loader2 size={14} className="animate-spin" /> {T.captureLookingUp} {stage.done} / {stage.total}
        </p>
      )}

      {stage.kind === "review" && (
        <>
          <h2 className="text-base font-bold text-ink">{T.captureReviewTitle}</h2>
          <ul className="flex flex-col gap-2">
            {items.map((it, i) => (
              <li key={i} className={`hk-card flex gap-3 p-3 ${it.on ? "" : "opacity-60"}`}>
                <input
                  type="checkbox"
                  checked={it.on}
                  onChange={(e) => edit(i, { on: e.target.checked })}
                  className="mt-2 h-4 w-4 shrink-0 accent-[var(--color-seal,#c8442f)]"
                />
                <div className="grid min-w-0 flex-1 grid-cols-2 gap-1.5">
                  <input lang="ja" value={it.term} onChange={(e) => edit(i, { term: e.target.value })} className={`${input} font-semibold`} />
                  <input lang="ja" value={it.reading} placeholder={T.reading} onChange={(e) => edit(i, { reading: e.target.value })} className={input} />
                  <input value={it.meaning} placeholder={T.meaningEn} onChange={(e) => edit(i, { meaning: e.target.value })} className={input} />
                  <input value={it.meaningMn} placeholder={T.mongolian} onChange={(e) => edit(i, { meaningMn: e.target.value })} className={input} />
                  {(it.inDeck || !it.found) && (
                    <p className="col-span-2 text-xs text-ink-mute">{it.inDeck ? T.captureAlreadyInDeck : T.captureNoLookup}</p>
                  )}
                </div>
              </li>
            ))}
          </ul>
          <label className="flex items-center gap-3 text-sm text-ink">
            {T.quickAddDeckLabel}
            <select value={deckId} onChange={(e) => setDeckId(e.target.value)} className="hk-input min-w-0 flex-1 rounded-control border border-line bg-surface px-3 py-2 text-sm">
              {decks.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name}
                </option>
              ))}
            </select>
          </label>
          <div className="flex flex-wrap gap-2">
            <button
              onClick={save}
              disabled={!deckId || !items.some((it) => it.on)}
              className="hk-btn hk-btn-primary px-4 py-2.5 text-sm disabled:opacity-50"
            >
              {T.captureSave(items.filter((it) => it.on).length)}
            </button>
            <button onClick={restart} className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm">
              {T.captureAnotherPhoto}
            </button>
          </div>
        </>
      )}

      {stage.kind === "saved" && (
        <div className="hk-card flex flex-col items-start gap-3 p-5">
          <p className="flex items-center gap-2 text-base font-semibold text-ink">
            <Check size={18} /> {T.captureSaved(stage.n)}
          </p>
          <div className="flex flex-wrap gap-2">
            <Link href={`/decks?deck=${deckId}`} className="hk-btn hk-btn-primary px-4 py-2 text-sm">
              {T.captureOpenDeck}
            </Link>
            <button onClick={restart} className="hk-btn hk-btn-quiet px-4 py-2 text-sm">
              {T.captureAnotherPhoto}
            </button>
          </div>
        </div>
      )}

      {error && <p className="text-sm text-ink-soft">{error}</p>}
    </div>
  );
}
