"use client";

import { useImmersive } from "../_lib/useImmersive";
import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Check, Eye, Grid3x3, List, PenLine, RotateCcw, Trash2, Undo2 } from "@/ui/icons";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import LoadingScene from "../review/battle/_components/LoadingScene";
import WritingPad from "./_components/WritingPad";
import {
  hasKanji,
  kanjiInOrder,
  kanjiOf,
  kanjiPositions,
  partialStrokes,
  planLesson,
  wordsForKanji,
  WORDS_PER_LESSON,
  type LessonStep,
} from "./_lib/lesson";
import { missMessage } from "./_lib/missMessage";
import { gradeStrokes, loadKanjiStrokes, type KanjiStrokes, type Polyline, type StrokeGrade } from "./_lib/strokes";

// Kanji writing lessons on the web — mobile's writing_setup.dart +
// writing_screen.dart. Pick a deck and words (or kanji); each new kanji climbs
// trace → some strokes → memory, then the whole word is written a kanji at a
// time. Kanji passed from memory are stored in learned_kanji (0026), shared
// with the phone. Practice only: answers are logged as 'drill' and nothing is
// rescheduled. The web has no ML Kit, so the stroke check (strokes.ts, pinned
// to mobile's grader by a shared fixture) is the whole judgement.

interface Word {
  id: string;
  deck_id: string;
  term: string;
  reading: string | null;
  meaning: string | null;
  meaning_mn: string | null;
  date_added: string;
}

interface Deck {
  id: string;
  name: string;
}

async function loadLearned(): Promise<Set<string>> {
  const { data, error } = await supabase.from("learned_kanji").select("kanji");
  return error ? new Set() : new Set((data ?? []).map((r: { kanji: string }) => r.kanji));
}

export default function WritingPage() {
  const [decks, setDecks] = useState<Deck[] | null>(null);
  const [words, setWords] = useState<Word[]>([]);
  const [learned, setLearned] = useState<Set<string>>(new Set());
  const [chosen, setChosen] = useState<Word[] | null>(null);

  useEffect(() => {
    (async () => {
      const [d, w, l] = await Promise.all([
        supabase.from("decks").select("id, name").eq("deleted", false).order("name"),
        supabase.from("words").select("id, deck_id, term, reading, meaning, meaning_mn, date_added").eq("deleted", false),
        loadLearned(),
      ]);
      setDecks((d.data as Deck[]) ?? []);
      setWords(((w.data as Word[]) ?? []).filter((x) => hasKanji(x.term)));
      setLearned(l);
    })();
  }, []);

  if (decks === null) return <LoadingScene label={T.loading} />;
  if (chosen) {
    return (
      <Lesson
        pool={chosen}
        learned={learned}
        onLearned={(k) => setLearned((s) => new Set(s).add(k))}
        onPick={() => setChosen(null)}
      />
    );
  }
  return <Setup decks={decks} words={words} learned={learned} onStart={setChosen} />;
}

// ---- Setup ---------------------------------------------------------------------

function Setup({
  decks,
  words,
  learned,
  onStart,
}: {
  decks: Deck[];
  words: Word[];
  learned: Set<string>;
  onStart: (words: Word[]) => void;
}) {
  const [deckId, setDeckId] = useState<string>("");
  const [view, setView] = useState<"words" | "kanji">("words");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [pickedKanji, setPickedKanji] = useState<string[]>([]);

  const candidates = useMemo(
    () =>
      words
        .filter((w) => !deckId || w.deck_id === deckId)
        .sort((a, b) => b.date_added.localeCompare(a.date_added)),
    [words, deckId]
  );
  const grid = useMemo(() => kanjiInOrder(candidates.map((w) => w.term)), [candidates]);
  const chosen =
    view === "words"
      ? candidates.filter((w) => picked.has(w.id))
      : wordsForKanji(pickedKanji, candidates, (w) => w.term);
  const hasNew = (w: Word) => kanjiOf(w.term).some((k) => !learned.has(k));

  function quickPick(onlyNew: boolean) {
    if (view === "words") setPicked(new Set(candidates.filter((w) => !onlyNew || hasNew(w)).map((w) => w.id)));
    else setPickedKanji(grid.filter((k) => !onlyNew || !learned.has(k)));
  }
  function clear() {
    setPicked(new Set());
    setPickedKanji([]);
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-6 sm:py-8">
      <h1 className="flex items-center gap-2 text-2xl font-bold text-ink">
        <PenLine size={22} className="text-seal" /> {T.writingTitle}
      </h1>
      <p className="mt-1 text-sm text-ink-soft">{T.writingDesc}</p>

      <div className="mt-5 flex flex-wrap items-center gap-2">
        <select
          value={deckId}
          onChange={(e) => {
            setDeckId(e.target.value);
            clear();
          }}
          aria-label={T.writingSetupDeck}
          className="rounded-control border border-line bg-surface px-3 py-2 text-sm"
        >
          <option value="">{T.writingAllDecks}</option>
          {decks.map((d) => (
            <option key={d.id} value={d.id}>
              {d.name}
            </option>
          ))}
        </select>
        <div className="flex gap-1 rounded-control bg-paper-dim p-1 text-sm">
          {(["words", "kanji"] as const).map((v) => (
            <button
              key={v}
              onClick={() => {
                setView(v);
                clear();
              }}
              className={`flex items-center gap-1.5 rounded-control px-3 py-1 font-medium ${
                view === v ? "bg-surface text-ink shadow-sm" : "text-ink-soft"
              }`}
            >
              {v === "words" ? <List size={14} /> : <Grid3x3 size={14} />}
              {v === "words" ? T.writingByWord : T.writingByKanji}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-3 text-sm">
        <button onClick={() => quickPick(true)} className="font-medium text-seal hover:underline">
          {T.writingPickNew}
        </button>
        <button onClick={() => quickPick(false)} className="font-medium text-seal hover:underline">
          {T.writingPickAll}
        </button>
        <button onClick={clear} className="font-medium text-seal hover:underline">
          {T.writingPickNone}
        </button>
        <span className="text-xs text-ink-mute">{T.writingLearnedLegend}</span>
      </div>

      {candidates.length === 0 ? (
        <p className="py-12 text-center text-sm text-ink-mute">{T.writingNoKanji}</p>
      ) : view === "words" ? (
        <ul className="mt-3 divide-y divide-line-soft rounded-card border border-line-soft bg-surface">
          {candidates.map((w) => (
            <li key={w.id}>
              <label className="flex cursor-pointer items-center gap-3 px-4 py-2.5">
                <input
                  type="checkbox"
                  checked={picked.has(w.id)}
                  onChange={() =>
                    setPicked((s) => {
                      const n = new Set(s);
                      if (n.has(w.id)) n.delete(w.id);
                      else n.add(w.id);
                      return n;
                    })
                  }
                  className="h-4 w-4"
                />
                <span className="text-lg font-bold">
                  {[...w.term].map((ch, i) => (
                    <span key={i} className={learned.has(ch) ? "text-emerald-600" : "text-ink"}>
                      {ch}
                    </span>
                  ))}
                </span>
                {w.reading && w.reading !== w.term && <span className="text-sm text-ink-mute">{w.reading}</span>}
                <span className="ml-auto truncate text-xs text-ink-mute">{w.meaning_mn || w.meaning}</span>
              </label>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mt-3 grid grid-cols-[repeat(auto-fill,minmax(56px,1fr))] gap-2">
          {grid.map((k) => {
            const on = pickedKanji.includes(k);
            return (
              <button
                key={k}
                onClick={() => setPickedKanji((s) => (on ? s.filter((x) => x !== k) : [...s, k]))}
                className={`relative aspect-square rounded-control border text-2xl font-bold transition ${
                  on ? "border-seal bg-seal-tint ring-2 ring-seal" : "border-line-soft bg-surface hover:border-seal"
                }`}
              >
                {k}
                {learned.has(k) && <span className="absolute right-1 top-0.5 text-xs text-emerald-600">✓</span>}
              </button>
            );
          })}
        </div>
      )}

      <div className="sticky bottom-0 mt-4 bg-paper/90 py-3 backdrop-blur">
        {view === "kanji" && pickedKanji.length > 0 && (
          <p className="mb-1.5 text-center text-xs text-ink-mute">{T.writingKanjiSelected(pickedKanji.length, chosen.length)}</p>
        )}
        <button
          disabled={chosen.length === 0}
          onClick={() => onStart(chosen)}
          className="hk-btn hk-btn-primary w-full py-3 text-sm disabled:opacity-50"
        >
          <PenLine size={16} /> {T.writingStartLesson(chosen.length)}
        </button>
      </div>
    </div>
  );
}

// ---- Lesson --------------------------------------------------------------------

async function cardIdsFor(wordIds: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  // In batches: a long in.(…) list overruns the URL length a proxy accepts.
  for (let i = 0; i < wordIds.length; i += 100) {
    const { data } = await supabase
      .from("cards")
      .select("id, word_id")
      .eq("template", "recognition")
      .in("word_id", wordIds.slice(i, i + 100));
    for (const r of (data as { id: string; word_id: string }[]) ?? []) out.set(r.word_id, r.id);
  }
  return out;
}

type Phase = "writing" | "correct" | "wrong" | "self";

function Lesson({
  pool,
  learned,
  onLearned,
  onPick,
}: {
  pool: Word[];
  learned: Set<string>;
  onLearned: (k: string) => void;
  onPick: () => void;
}) {
  useImmersive();
  const [offset, setOffset] = useState(0);
  const [words, setWords] = useState<Word[]>([]);
  const [steps, setSteps] = useState<LessonStep[] | null>(null);
  const [stepIndex, setStepIndex] = useState(0);
  const [strokeData, setStrokeData] = useState<Map<string, KanjiStrokes | null>>(new Map());
  const [cardIds, setCardIds] = useState<Map<string, string>>(new Map());

  const [phase, setPhase] = useState<Phase>("writing");
  const [ink, setInk] = useState<Polyline[]>([]);
  const [grade, setGrade] = useState<StrokeGrade | null>(null);
  const [showAnswer, setShowAnswer] = useState(false);
  const [slot, setSlot] = useState(0);
  const [demoKey, setDemoKey] = useState(0);
  const [missed, setMissed] = useState(false);
  const [missedWords, setMissedWords] = useState<Set<number>>(new Set());
  const [stats, setStats] = useState({ newKanji: 0, checks: 0, firstTry: 0 });

  const startLesson = useCallback(
    async (from: number) => {
      const next = pool.slice(from, from + WORDS_PER_LESSON);
      setSteps(null);
      const kanji = [...new Set(next.flatMap((w) => kanjiOf(w.term)))];
      const [loaded, ids] = await Promise.all([
        Promise.all(kanji.map(async (k) => [k, await loadKanjiStrokes(k)] as const)),
        cardIdsFor(next.map((w) => w.id)),
      ]);
      setStrokeData(new Map(loaded));
      setCardIds(ids);
      setWords(next);
      setOffset(from + next.length);
      setSteps(planLesson(next.map((w) => w.term), learned));
      setStepIndex(0);
      setMissedWords(new Set());
      setStats({ newKanji: 0, checks: 0, firstTry: 0 });
      resetStep();
    },
    // learned is read at lesson start on purpose; pool is fixed per selection.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [pool]
  );

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- start the first lesson
    void startLesson(0);
  }, [startLesson]);

  function resetStep() {
    setPhase("writing");
    setInk([]);
    setGrade(null);
    setShowAnswer(false);
    setMissed(false);
    setSlot(0);
    setDemoKey((k) => k + 1);
  }

  if (!steps) return <LoadingScene label={T.writingPreparing} />;
  const step = steps[stepIndex];

  if (!step) {
    const accuracy = stats.checks === 0 ? 100 : Math.round((stats.firstTry * 100) / stats.checks);
    return (
      <div className="mx-auto max-w-md px-4 py-12 text-center">
        <h1 className="text-3xl font-extrabold text-ink">{T.writingLessonDone}</h1>
        <div className="mt-6 grid grid-cols-3 gap-2">
          {[
            [String(words.length), T.writingStatWords],
            [String(stats.newKanji), T.writingStatNewKanji],
            [`${accuracy}%`, T.writingStatAccuracy],
          ].map(([v, l]) => (
            <div key={l} className="hk-card py-3">
              <p className="text-2xl font-extrabold text-ink">{v}</p>
              <p className="text-xs text-ink-mute">{l}</p>
            </div>
          ))}
        </div>
        <div className="mt-6 space-y-2">
          {offset < pool.length && (
            <button onClick={() => startLesson(offset)} className="hk-btn hk-btn-primary w-full py-3 text-sm">
              {T.writingNextLesson}
            </button>
          )}
          <button onClick={onPick} className="hk-btn w-full py-3 text-sm">
            {T.writingBackToPick}
          </button>
          <Link href="/decks/review" className="hk-btn w-full py-3 text-sm">
            {T.writingFinish}
          </Link>
        </div>
        <p className="mt-6 text-xs text-ink-mute">{T.kanjiVgCredit}</p>
      </div>
    );
  }

  const word = words[step.wordIndex];
  const chars = [...word.term];
  const positions = kanjiPositions(word.term);
  const target = step.kind === "word" ? chars[positions[Math.min(slot, positions.length - 1)]] : step.char!;
  const strokes = strokeData.get(target) ?? null;
  const highlight = step.kind === "word" ? positions[Math.min(slot, positions.length - 1)] : chars.indexOf(step.char!);
  const guide = !strokes
    ? 0
    : showAnswer
      ? strokes.polylines.length
      : step.kind === "trace"
        ? strokes.polylines.length
        : step.kind === "partial"
          ? partialStrokes(strokes.polylines.length)
          : 0;
  const meaning = [word.meaning_mn, word.meaning].filter(Boolean).join(" · ");
  const revealed = (i: number) =>
    !positions.includes(i) ||
    (step.kind === "trace" && i === highlight) ||
    (step.kind === "word" && positions.indexOf(i) < slot) ||
    (i === highlight && (phase === "correct" || showAnswer || phase === "self"));

  function logWord(wordIndex: number) {
    const cardId = cardIds.get(words[wordIndex].id);
    if (!cardId) return;
    // Practice only: 'drill' is review_card's log-only branch. Not awaited —
    // a slow insert must not hold the lesson.
    void supabase
      .rpc("review_card", {
        p_card_id: cardId,
        p_rating: missedWords.has(wordIndex) ? "again" : "good",
        p_duration_ms: null,
        p_log_id: crypto.randomUUID(),
        p_source: "drill",
      })
      .then(undefined, () => {});
  }

  function next() {
    if (step.kind === "word" && slot + 1 < positions.length) {
      setSlot((s) => s + 1);
      setPhase("writing");
      setInk([]);
      setGrade(null);
      setShowAnswer(false);
      setMissed(false);
      return;
    }
    const nextStep = steps![stepIndex + 1];
    if (!nextStep || nextStep.wordIndex !== step.wordIndex) logWord(step.wordIndex);
    setStepIndex((i) => i + 1);
    resetStep();
  }

  function markLearned() {
    if (step.kind !== "blank" || learned.has(target)) return;
    onLearned(target);
    setStats((s) => ({ ...s, newKanji: s.newKanji + 1 }));
    // Shared with the phone; a failed write catches up next time either
    // app syncs (mobile uploads its local set).
    void (async () => {
      const { data } = await supabase.auth.getUser();
      if (data.user) {
        await supabase
          .from("learned_kanji")
          .upsert({ user_id: data.user.id, kanji: target }, { onConflict: "user_id,kanji", ignoreDuplicates: true });
      }
    })();
  }

  function check() {
    if (!ink.length) return;
    if (!strokes) {
      // Nothing to grade against: show the kanji and let the learner judge.
      setPhase("self");
      return;
    }
    const g = gradeStrokes(ink, strokes.polylines);
    setStats((s) => ({ ...s, checks: s.checks + 1, firstTry: s.firstTry + (g.ok && !missed ? 1 : 0) }));
    setGrade(g);
    if (g.ok) {
      setPhase("correct");
      markLearned();
    } else {
      setPhase("wrong");
      setMissed(true);
      setShowAnswer(true);
      setMissedWords((m) => new Set(m).add(step.wordIndex));
    }
  }

  function selfJudge(ok: boolean) {
    setStats((s) => ({ ...s, checks: s.checks + 1, firstTry: s.firstTry + (ok ? 1 : 0) }));
    if (ok) {
      setPhase("correct");
      markLearned();
    } else {
      setMissedWords((m) => new Set(m).add(step.wordIndex));
      setShowAnswer(true);
      setPhase("wrong");
      setMissed(true);
    }
  }

  const instruction =
    step.kind === "trace"
      ? T.writingStepTrace
      : step.kind === "partial"
        ? T.writingStepPartial
        : step.kind === "blank"
          ? T.writingStepBlank
          : T.writingStepWord;

  return (
    <div className="mx-auto max-w-xl px-4 py-5">
      <div className="flex items-center gap-3">
        <button onClick={onPick} aria-label={T.writingBackToPick} className="text-ink-soft hover:text-ink">
          <ArrowLeft size={18} />
        </button>
        <div className="h-3 flex-1 overflow-hidden rounded-full bg-line-soft">
          <div className="h-full bg-emerald-500 transition-all" style={{ width: `${(stepIndex / steps.length) * 100}%` }} />
        </div>
      </div>

      <h2 className="mt-4 text-lg font-bold text-ink">{instruction}</h2>
      <div className="mt-3 flex justify-center gap-1">
        {chars.map((ch, i) => (
          <span
            key={i}
            className={`flex h-12 w-11 items-center justify-center rounded-control border-2 text-3xl font-bold ${
              i === highlight ? (phase === "wrong" ? "border-red-500 bg-seal-tint" : "border-seal bg-seal-tint") : "border-transparent"
            } ${revealed(i) ? "text-ink" : "text-ink-mute/50"}`}
          >
            {revealed(i) ? ch : "?"}
          </span>
        ))}
      </div>
      <p className="mt-1 text-center text-sm text-ink-mute">
        {[word.reading, meaning].filter(Boolean).join("  ·  ")}
      </p>

      <div className="mt-4">
        <WritingPad
          strokes={strokes}
          guideCount={guide}
          answer={showAnswer && phase !== "writing" ? true : showAnswer}
          demo={step.kind === "trace" && !showAnswer && !!strokes}
          demoKey={demoKey}
          ink={ink}
          onInk={(next) => {
            // Writing again after a miss starts on a clean pad.
            if (phase === "wrong") {
              setPhase("writing");
              setInk(next.slice(-1));
              return;
            }
            if (phase === "writing") setInk(next);
          }}
          locked={phase === "correct" || phase === "self"}
          borderColor={phase === "correct" ? "#16a34a" : phase === "wrong" ? "#dc2626" : undefined}
          badInk={phase === "wrong" ? (grade?.stroke ?? null) : null}
          focusStroke={phase === "wrong" ? (grade?.stroke ?? null) : null}
        />
      </div>

      <div className="mt-4">
        {phase === "correct" ? (
          <div className="rounded-card bg-emerald-50 p-3">
            <p className="font-extrabold text-emerald-700">{T.writingCorrect}</p>
            <button onClick={next} className="hk-btn mt-2 w-full bg-emerald-600 py-3 text-sm text-white hover:bg-emerald-700">
              {T.writingContinue}
            </button>
          </div>
        ) : phase === "wrong" ? (
          <div className="rounded-card bg-red-50 p-3">
            <p className="font-extrabold text-red-700">{T.writingWrong}</p>
            {grade && !grade.ok && <p className="text-sm text-red-700">{missMessage(grade)}</p>}
            <div className="mt-2 grid grid-cols-2 gap-2">
              <button onClick={next} className="hk-btn py-3 text-sm">
                {T.writingSkip}
              </button>
              <button
                onClick={() => {
                  setPhase("writing");
                  setInk([]);
                }}
                className="hk-btn bg-red-600 py-3 text-sm text-white hover:bg-red-700"
              >
                {T.writingRetry}
              </button>
            </div>
          </div>
        ) : phase === "self" ? (
          <div className="rounded-card bg-paper-dim p-3">
            <p className="text-sm text-ink-soft">{T.writingNoStrokeData}</p>
            <div className="mt-2 grid grid-cols-2 gap-2">
              <button onClick={() => selfJudge(false)} className="hk-btn py-3 text-sm">
                {T.writingSelfWrong}
              </button>
              <button onClick={() => selfJudge(true)} className="hk-btn hk-btn-primary py-3 text-sm">
                <Check size={15} /> {T.writingSelfRight}
              </button>
            </div>
          </div>
        ) : (
          <div className="flex items-center gap-2">
            <button aria-label={T.writingUndo} disabled={!ink.length} onClick={() => setInk(ink.slice(0, -1))} className="hk-btn px-3 py-3 disabled:opacity-40">
              <Undo2 size={16} />
            </button>
            <button aria-label={T.writingClear} disabled={!ink.length} onClick={() => setInk([])} className="hk-btn px-3 py-3 disabled:opacity-40">
              <Trash2 size={16} />
            </button>
            {step.kind === "trace" && strokes ? (
              <button aria-label={T.writingReplay} onClick={() => setDemoKey((k) => k + 1)} className="hk-btn px-3 py-3">
                <RotateCcw size={16} />
              </button>
            ) : (
              <button
                aria-label={T.writingReveal}
                disabled={showAnswer || !strokes}
                onClick={() => setShowAnswer(true)}
                className="hk-btn px-3 py-3 disabled:opacity-40"
              >
                <Eye size={16} />
              </button>
            )}
            <button disabled={!ink.length} onClick={check} className="hk-btn hk-btn-primary flex-1 py-3 text-sm disabled:opacity-50">
              {T.writingCheck}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
