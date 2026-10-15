"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Download, Loader2, RefreshCw, Trash2, Volume2 } from "@/ui/icons";
import { findExample } from "@/lib/examples";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { buildAudioDeck, cueAt, DEFAULT_OPTIONS, type AudioDeck, type AudioOptions } from "../_lib/audioDeck";
import { deleteAudioDeck, fetchClip, loadAudioDeck, saveAudioDeck } from "../_lib/audioStore";

const OPTIONS_KEY = "hanko.audio.options";

function storedOptions(): AudioOptions {
  try {
    return { ...DEFAULT_OPTIONS, ...JSON.parse(localStorage.getItem(OPTIONS_KEY) ?? "{}") };
  } catch {
    return DEFAULT_OPTIONS;
  }
}

function clock(ms: number) {
  const s = Math.round(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/**
 * Audio decks on the web — mobile's features/audio, in the browser: a deck
 * turned into one MP3 (_lib/audioDeck.ts), kept in this browser, played here
 * with the word being spoken shown large (Mongolian has no voice, so it's
 * text), and downloadable to listen anywhere — a music app plays it with the
 * screen locked, which a web page can't promise.
 */
export default function AudioDecks() {
  const params = useSearchParams();
  const [decks, setDecks] = useState<{ id: string; name: string }[]>([]);
  const [deckId, setDeckId] = useState<string | null>(params.get("deck"));
  const [options, setOptions] = useState<AudioOptions>(DEFAULT_OPTIONS);
  const [built, setBuilt] = useState<AudioDeck | null>(null);
  const [progress, setProgress] = useState<{ label: string; pct: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cue, setCue] = useState(0);
  const audio = useRef<HTMLAudioElement>(null);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reads localStorage once, after mount
    setOptions(storedOptions());
    supabase
      .from("decks")
      .select("id, name")
      .eq("deleted", false)
      .order("name")
      .then(({ data }) => {
        const list = (data as { id: string; name: string }[]) ?? [];
        setDecks(list);
        setDeckId((id) => id ?? list[0]?.id ?? null);
      });
  }, []);

  useEffect(() => {
    if (!deckId) return;
    let live = true;
    loadAudioDeck(deckId)
      .then((d) => {
        if (!live) return;
        setBuilt(d ?? null);
        setCue(0);
        setError(null);
      })
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [deckId]);

  const url = useMemo(() => (built ? URL.createObjectURL(new Blob([built.mp3], { type: "audio/mpeg" })) : null), [built]);
  useEffect(() => () => void (url && URL.revokeObjectURL(url)), [url]);

  // The lock screen / notification shade shows the word being spoken, and its
  // previous/next buttons step a word at a time.
  const current = built?.cues[cue];
  useEffect(() => {
    if (!built || !current || !("mediaSession" in navigator)) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: current.term,
      artist: [current.reading, current.meaningMn || current.meaning].filter(Boolean).join(" · "),
      album: built.deckName,
      artwork: [{ src: "/icon-512.png", sizes: "512x512", type: "image/png" }],
    });
    const seek = (i: number) => {
      const el = audio.current;
      const c = built.cues[Math.max(0, Math.min(built.cues.length - 1, i))];
      if (el && c) el.currentTime = c.startMs / 1000;
    };
    navigator.mediaSession.setActionHandler("previoustrack", () => seek(cue - 1));
    navigator.mediaSession.setActionHandler("nexttrack", () => seek(cue + 1));
  }, [built, current, cue]);

  function setOption<K extends keyof AudioOptions>(k: K, v: AudioOptions[K]) {
    const next = { ...options, [k]: v };
    setOptions(next);
    try {
      localStorage.setItem(OPTIONS_KEY, JSON.stringify(next));
    } catch {}
  }

  async function build() {
    if (!deckId) return;
    const deck = decks.find((d) => d.id === deckId);
    setError(null);
    setProgress({ label: T.audioBuilding(0, 0), pct: 0 });
    const { data: words, error: wordsError } = await supabase
      .from("words")
      .select("*")
      .eq("deck_id", deckId)
      .eq("deleted", false)
      .order("date_added");
    if (wordsError || !words?.length) {
      setProgress(null);
      setError(wordsError ? T.audioDeckFailed : T.audioNoWords);
      return;
    }
    const result = await buildAudioDeck({ id: deckId, name: deck?.name ?? "" }, words, options, {
      clip: fetchClip,
      findExample: (t) => findExample(t),
      onSentenceProgress: (done, total) => setProgress({ label: T.audioFindingSentences(done, total), pct: (done / total) * 100 }),
      onProgress: (done, total) => setProgress({ label: T.audioBuilding(done, total), pct: (done / total) * 100 }),
    });
    setProgress(null);
    if (!result) {
      setError(T.audioDeckFailed);
      return;
    }
    await saveAudioDeck(result).catch(() => {});
    setBuilt(result);
    setCue(0);
  }

  async function remove() {
    if (!deckId) return;
    audio.current?.pause();
    await deleteAudioDeck(deckId).catch(() => {});
    setBuilt(null);
  }

  const toggle = (on: boolean, label: string, flip: () => void) => (
    <button role="switch" aria-checked={on} onClick={flip} className="flex w-full items-center justify-between gap-4 py-1.5 text-left text-sm text-ink">
      {label}
      <span className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${on ? "bg-seal" : "bg-paper-deep"}`}>
        <span className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all ${on ? "left-[22px]" : "left-0.5"}`} />
      </span>
    </button>
  );
  const choice = <V extends number>(label: string, value: V, values: V[], show: (v: V) => string, pick: (v: V) => void) => (
    <div className="flex items-center justify-between gap-4 py-1.5 text-sm text-ink">
      {label}
      <div className="flex gap-1">
        {values.map((v) => (
          <button
            key={v}
            onClick={() => pick(v)}
            aria-pressed={value === v}
            className={`rounded-control border px-2.5 py-1 text-xs font-medium transition ${
              value === v ? "border-seal bg-seal-tint text-seal" : "border-line text-ink-soft hover:bg-paper-dim"
            }`}
          >
            {show(v)}
          </button>
        ))}
      </div>
    </div>
  );

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-4 px-4 py-6 sm:py-10">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold tracking-tight text-ink">
          <Volume2 size={22} /> {T.audioTitle}
        </h1>
        <p className="mt-1 text-sm text-ink-soft">{T.audioIntro}</p>
      </div>

      <label className="flex items-center gap-3 text-sm text-ink">
        {T.audioDeckLabel}
        <select
          value={deckId ?? ""}
          onChange={(e) => setDeckId(e.target.value || null)}
          className="hk-input min-w-0 flex-1 rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink"
        >
          {decks.map((d) => (
            <option key={d.id} value={d.id}>
              {d.name}
            </option>
          ))}
        </select>
      </label>

      {built && url && current && (
        <section className="hk-card flex flex-col gap-4 p-5">
          <div className="text-center">
            <p lang="ja" className="text-4xl font-bold text-ink">
              {current.term}
            </p>
            {current.reading && current.reading !== current.term && <p className="mt-1 text-base text-ink-soft">{current.reading}</p>}
            {current.meaningMn && <p className="mt-3 text-lg font-semibold text-ink">{current.meaningMn}</p>}
            {current.meaning && <p className="text-sm text-ink-mute">{current.meaning}</p>}
            {current.sentence && (
              <p lang="ja" className="mt-3 text-sm text-ink-soft">
                {current.sentence}
                {current.sentenceEn && <span className="block text-xs text-ink-mute">{current.sentenceEn}</span>}
              </p>
            )}
          </div>
          <audio
            ref={audio}
            src={url}
            controls
            onTimeUpdate={(e) => setCue(cueAt(built.cues, e.currentTarget.currentTime * 1000))}
            className="w-full"
          />
          <p className="text-center text-xs text-ink-mute">
            {T.audioSummary(built.cues.length, clock(built.durationMs))}
            {built.skipped > 0 && ` · ${T.audioSkipped(built.skipped)}`}
          </p>
          <ol className="max-h-56 overflow-y-auto rounded-control border border-line-soft">
            {built.cues.map((c, i) => (
              <li key={i}>
                <button
                  onClick={() => {
                    if (!audio.current) return;
                    audio.current.currentTime = c.startMs / 1000;
                    audio.current.play().catch(() => {});
                  }}
                  className={`flex w-full items-baseline gap-3 px-3 py-1.5 text-left text-sm transition hover:bg-paper-dim ${
                    i === cue ? "bg-seal-tint/60 font-semibold text-ink" : "text-ink-soft"
                  }`}
                >
                  <span className="w-10 shrink-0 text-xs tabular-nums text-ink-mute">{clock(c.startMs)}</span>
                  <span lang="ja">{c.term}</span>
                  <span className="truncate text-xs text-ink-mute">{c.meaningMn || c.meaning}</span>
                </button>
              </li>
            ))}
          </ol>
          <div className="flex flex-wrap gap-2">
            <a href={url} download={`${built.deckName || "hanko"}.mp3`} className="hk-btn hk-btn-primary px-4 py-2 text-sm">
              <Download size={15} /> {T.audioDownload}
            </a>
            <button onClick={remove} className="hk-btn hk-btn-quiet px-4 py-2 text-sm">
              <Trash2 size={15} /> {T.audioDelete}
            </button>
          </div>
          <p className="text-xs text-ink-mute">{T.audioMnNote}</p>
        </section>
      )}

      <section className="hk-card p-5">
        <h2 className="mb-2 text-base font-bold text-ink">{T.audioOptionsTitle}</h2>
        {toggle(options.english, T.audioEnglish, () => setOption("english", !options.english))}
        {choice(T.audioRepeat, options.repeat, [1, 2, 3], T.audioRepeatN, (v) => setOption("repeat", v))}
        {choice(T.audioPause, options.pauseMs, [1000, 1500, 3000], (v) => T.audioPauseS(v / 1000), (v) => setOption("pauseMs", v))}
        {toggle(options.shuffle, T.audioShuffle, () => setOption("shuffle", !options.shuffle))}
        {toggle(options.sentences, T.audioSentences, () => setOption("sentences", !options.sentences))}
        {options.sentences && <p className="text-xs text-ink-mute">{T.audioSentencesHint}</p>}

        <div className="mt-4">
          {progress ? (
            <div>
              <p className="flex items-center gap-2 text-sm text-ink-soft">
                <Loader2 size={14} className="animate-spin" /> {progress.label}
              </p>
              <div className="mt-2 h-2 overflow-hidden rounded-full bg-line-soft">
                <div className="h-full bg-seal transition-all" style={{ width: `${progress.pct}%` }} />
              </div>
            </div>
          ) : (
            <button onClick={build} disabled={!deckId} className="hk-btn hk-btn-primary px-4 py-2.5 text-sm disabled:opacity-50">
              {built ? <RefreshCw size={15} /> : <Volume2 size={15} />} {built ? T.audioRegenerate : T.audioCreate}
            </button>
          )}
          {error && <p className="mt-2 text-sm text-ink-soft">{error}</p>}
        </div>
      </section>
    </div>
  );
}
