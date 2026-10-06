"use client";

import { useState, type ReactNode } from "react";
import { PenLine, Trash2, Undo2 } from "lucide-react";
import { T } from "../../../_lib/strings";
import type { QueueCard } from "../../../_lib/types";
import WritingPad from "../../../writing/_components/WritingPad";
import { kanjiPositions } from "../../../writing/_lib/lesson";
import { missMessage } from "../../../writing/_lib/missMessage";
import { gradeStrokes, type KanjiStrokes, type Polyline, type StrokeGrade } from "../../../writing/_lib/strokes";

const RED = "#dc2626";

/**
 * A Monster Hunt "write it" question — mobile's _WriteQuestion. Reading and
 * meaning are the prompt; the word is a row of boxes, kana given, its kanji
 * written one at a time on the pad. A miss draws the right kanji in red on the
 * same pad and holds the clock (`onHold`) until the learner continues; only
 * then does the miss land (`onResult(false)`).
 *
 * Re-key it per question: ink and the miss belong to one question.
 */
export default function WriteQuestion({
  card,
  slot,
  strokes,
  disabled,
  timer,
  onHold,
  onResult,
}: {
  card: QueueCard;
  /** Which of the word's kanji is being written. */
  slot: number;
  strokes: Map<string, KanjiStrokes | null>;
  disabled: boolean;
  timer: ReactNode;
  onHold: () => void;
  onResult: (ok: boolean) => void;
}) {
  const [ink, setInk] = useState<Polyline[]>([]);
  const [miss, setMiss] = useState<StrokeGrade | null>(null);

  const chars = [...card.term];
  const positions = kanjiPositions(card.term);
  const current = positions[Math.min(slot, positions.length - 1)];
  const target = strokes.get(chars[current]) ?? null;
  const meaning = card.meaning_mn || card.meaning || "";

  function check() {
    if (!ink.length || !target || disabled) return;
    const g = gradeStrokes(ink, target.polylines);
    if (g.ok) {
      setInk([]);
      onResult(true);
    } else {
      setMiss(g);
      onHold();
    }
  }

  return (
    <div className="flex w-full flex-col gap-3 text-left">
      <div className="flex items-center gap-2">
        <PenLine size={18} className="shrink-0 text-seal" />
        <span className="min-w-0 flex-1 truncate text-xl font-extrabold text-ink">{card.reading ?? ""}</span>
        <div className="flex gap-1">
          {chars.map((ch, i) => {
            const shown = !positions.includes(i) || positions.indexOf(i) < slot || (i === current && miss !== null);
            const isCurrent = i === current;
            return (
              <span
                key={i}
                className={`flex h-10 w-9 items-center justify-center rounded-control border-2 text-2xl font-extrabold ${
                  isCurrent ? `bg-seal-tint ${miss ? "border-red-600" : "border-seal"}` : "border-transparent"
                } ${isCurrent && miss ? "text-red-600" : "text-ink"}`}
              >
                {shown ? ch : "?"}
              </span>
            );
          })}
        </div>
      </div>
      {meaning && <p className="-mt-2 truncate text-sm text-ink-mute">{meaning}</p>}
      {timer}
      {/* What went wrong, right above the pad it's drawn on. Fixed height so
          the pad doesn't jump when it appears. */}
      <p className="h-5 truncate text-center text-sm font-bold text-red-600">{miss ? missMessage(miss) : ""}</p>
      <div className="mx-auto w-full max-w-[300px] xl:max-w-[340px]">
        <WritingPad
          strokes={target}
          // The correction: every stroke of the right kanji, in red, numbered,
          // under what was drawn.
          guideCount={miss ? (target?.polylines.length ?? 0) : 0}
          answer={miss !== null}
          ink={ink}
          onInk={setInk}
          locked={miss !== null || disabled}
          borderColor={miss ? RED : undefined}
          badInk={miss?.stroke ?? null}
          focusStroke={miss?.stroke ?? null}
        />
      </div>
      {miss ? (
        <button
          onClick={() => onResult(false)}
          className="hk-btn w-full bg-red-600 py-3 text-sm text-white hover:bg-red-700"
        >
          {T.writingContinue}
        </button>
      ) : (
        <div className="flex items-center gap-2">
          <button
            aria-label={T.writingUndo}
            disabled={!ink.length || disabled}
            onClick={() => setInk(ink.slice(0, -1))}
            className="hk-btn px-3 py-3 disabled:opacity-40"
          >
            <Undo2 size={16} />
          </button>
          <button
            aria-label={T.writingClear}
            disabled={!ink.length || disabled}
            onClick={() => setInk([])}
            className="hk-btn px-3 py-3 disabled:opacity-40"
          >
            <Trash2 size={16} />
          </button>
          <button
            disabled={!ink.length || disabled}
            onClick={check}
            className="hk-btn hk-btn-primary flex-1 py-3 text-sm disabled:opacity-50"
          >
            {T.writingCheck}
          </button>
        </div>
      )}
    </div>
  );
}
