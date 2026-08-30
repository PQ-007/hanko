import type { QuizOption } from "../_lib/quiz";

// Replaces RatingButtons for this mode only — self-rating and multiple
// choice are fundamentally different interactions. Classic mode's
// RatingButtons is untouched and not reused here.
//
// Letter badges are fixed per GRID POSITION (A/B/C/D), not per correctness —
// the player doesn't know in advance which slot holds the right answer, and
// the options are already shuffled by quiz.ts, so a fixed colour-per-slot
// scheme reads as "four choices," never as a hint.
const SLOT_STYLE = [
  { letter: "A", className: "bg-emerald-500" },
  { letter: "B", className: "bg-red-500" },
  { letter: "C", className: "bg-blue-500" },
  { letter: "D", className: "bg-amber-500" },
];

export default function QuizOptions({
  options,
  disabled,
  onPick,
}: {
  options: QuizOption[];
  disabled: boolean;
  onPick: (option: QuizOption) => void;
}) {
  return (
    <div className="grid w-full grid-cols-1 gap-2.5 sm:grid-cols-2">
      {options.map((opt, i) => {
        const slot = SLOT_STYLE[i] ?? SLOT_STYLE[0];
        return (
          <button
            key={`${opt.term}-${i}`}
            disabled={disabled}
            onClick={() => onPick(opt)}
            // Fixed height, not min-height: a `words` row's meaning field can
            // hold a long semicolon-separated synonym list (real example from
            // a live session: one option ran 10 lines while its neighbour ran
            // one). Left unbounded, each question resized the whole card and
            // dragged the fighters around with it — and nobody can read 10
            // lines inside a 10-second timer anyway. `line-clamp-3` plus a
            // fixed height makes every option the same size, so the card's
            // height is identical for every question in the session.
            className="flex h-[86px] items-start gap-2.5 overflow-hidden rounded-control border border-black/10 bg-white/70 px-3 py-2.5 text-left text-sm text-ink shadow-sm transition hover:border-black/20 hover:bg-white disabled:pointer-events-none disabled:opacity-60 xl:h-[108px] xl:gap-3 xl:px-4 xl:py-3 xl:text-base"
          >
            <span
              className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[11px] font-bold text-white xl:h-6 xl:w-6 xl:text-xs ${slot.className}`}
            >
              {slot.letter}
            </span>
            <span className="line-clamp-3 leading-snug">{opt.answerText}</span>
            {/* The number the key binding uses, shown so the shortcut is
                discoverable rather than folklore. Hidden on touch, where there
                is no keyboard to press it with. */}
            <kbd className="ml-auto hidden shrink-0 self-start rounded border border-black/10 px-1 text-[10px] font-medium text-ink-mute lg:block">
              {i + 1}
            </kbd>
          </button>
        );
      })}
    </div>
  );
}
