"use client";

import Link from "next/link";
import { Dumbbell, GraduationCap, Settings2, Swords, Users, X } from "lucide-react";
import { T } from "../_lib/strings";
import { useModalChrome } from "../_lib/useModal";
import { MIN_WORDS_FOR_BATTLE } from "../review/battle/_lib/quiz";
import ModeRow from "./ModeRow";

// The mode chooser, condensed into a dialog.
//
// Both dashboards' "Бүгдийг нь давтах" buttons linked directly to
// /decks/practice, which is one of four modes and the least interesting one.
// The chooser at /decks/review already existed; nothing on either dashboard
// pointed at it. This asks the question in place rather than making the
// choice on the user's behalf, and still offers the full page for the two
// things it can't fit — deck scope and the hero picker.
//
// `wordCount` gates Monster Hunt the same way the chooser page does: below
// four words there aren't enough distractors to build a question
// (_lib/quiz.ts), so offering it would be a dead end. Null means "not known
// yet" and is treated as unlocked — the arena's own empty state catches it.
export default function ReviewModeModal({
  onClose,
  wordCount = null,
  dueNow = null,
}: {
  onClose: () => void;
  wordCount?: number | null;
  dueNow?: number | null;
}) {
  useModalChrome(onClose);

  const battleLocked = wordCount !== null && wordCount < MIN_WORDS_FOR_BATTLE;
  const nothingDue = dueNow !== null && dueNow === 0;

  return (
    <div
      onClick={onClose}
      role="dialog"
      aria-modal
      aria-label={T.chooseModeTitle}
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/40 p-4"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="my-auto w-full max-w-lg rounded-card bg-paper p-5 shadow-2xl"
      >
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            {/* Lead with the number when it's known, the question when it
                isn't — same order of priority the chooser page uses. */}
            <h2 className="text-lg font-semibold text-ink">
              {dueNow === null
                ? T.chooseModeTitle
                : nothingDue
                  ? T.practiceNothingDue
                  : T.practiceDueHeadline(dueNow)}
            </h2>
            {/* Only when it adds something. With the count unknown the
                heading is already the question, and repeating it underneath
                read as a rendering bug. */}
            {(dueNow !== null || nothingDue) && (
              <p className="mt-0.5 text-xs text-ink-mute">
                {nothingDue ? T.practiceNothingDueSub : T.chooseModeTitle}
              </p>
            )}
          </div>
          <button
            onClick={onClose}
            title={T.closeLabel}
            aria-label={T.closeLabel}
            className="shrink-0 rounded-control p-1 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
          >
            <X size={18} />
          </button>
        </div>

        <div className="mt-4 flex flex-col gap-2.5">
          {/* 1 — Monster Hunt, the flagship. */}
          <ModeRow
            href={battleLocked ? undefined : "/decks/review/battle"}
            onNavigate={onClose}
            icon={<Swords size={19} />}
            iconClass={
              battleLocked
                ? "bg-paper-dim text-ink-mute"
                : "bg-seal text-paper"
            }
            title={T.battleModeTitle}
            desc={battleLocked ? T.battleLocked(MIN_WORDS_FOR_BATTLE) : T.battleModeDesc}
            badge={battleLocked ? T.lockedBadge : undefined}
            highlight={!battleLocked && !nothingDue}
          />

          {/* 2 — Free practice. The only option that still does something on a
              finished day, so that's the one day it gets promoted. */}
          <ModeRow
            href="/decks/review/battle?mode=free"
            onNavigate={onClose}
            icon={<Dumbbell size={19} />}
            iconClass="bg-sky-50 text-sky-700 ring-1 ring-sky-100"
            title={T.freeModeTitle}
            desc={T.freeModeDesc}
            highlight={nothingDue}
          />

          {/* 3 — Classic: where this button used to go without asking. */}
          <ModeRow
            href="/decks/practice"
            onNavigate={onClose}
            icon={<GraduationCap size={19} />}
            iconClass="bg-paper-dim text-ink ring-1 ring-line-soft"
            title={T.classicModeTitle}
            desc={T.classicModeDesc}
          />

          {/* 4 — PvP. Built now (PVP.md): a bot opponent needs no second
              player, so this is never a dead end even alone. */}
          <ModeRow
            href="/decks/review/duel"
            onNavigate={onClose}
            icon={<Users size={19} />}
            iconClass="bg-violet-50 text-violet-700 ring-1 ring-violet-100"
            title={T.multiplayerTitle}
            desc={T.multiplayerDesc}
          />
        </div>

        {/* The two things the dialog can't fit live one click away. */}
        <Link
          href="/decks/review"
          onNavigate={onClose}
          className="mt-3 flex items-center justify-center gap-1.5 rounded-control px-3 py-2 text-xs font-medium text-ink-soft transition hover:bg-paper-dim hover:text-ink"
        >
          <Settings2 size={13} /> {T.moreModeOptions}
        </Link>
      </div>
    </div>
  );
}
