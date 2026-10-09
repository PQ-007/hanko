import { T } from "../../../_lib/strings";
import type { HeadToHead } from "../../../_lib/social";
import { lastResults, recordTotal } from "../_lib/record";

// Your face-to-face record, drawn for the dark arena: the score as two big
// numbers, a bar split by results, and the last five fights as chips. Used
// before a match (the intro) and after it (the result, now one fight longer).

const CHIP = {
  win: "bg-emerald-400/20 text-emerald-300 ring-emerald-400/40",
  loss: "bg-red-400/20 text-red-300 ring-red-400/40",
  draw: "bg-amber-400/20 text-amber-200 ring-amber-400/40",
} as const;
const LETTER = { win: T.duelRecWinLetter, loss: T.duelRecLossLetter, draw: T.duelRecDrawLetter } as const;

export default function H2HRecord({
  record,
  youName,
  themName,
  compact = false,
}: {
  record: HeadToHead;
  youName: string;
  themName: string;
  compact?: boolean;
}) {
  const total = recordTotal(record);
  const last = lastResults(record, 5);

  if (total === 0) {
    return (
      <div className="rounded-card bg-white/5 px-4 py-4 text-center ring-1 ring-white/10">
        <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-paper/40">{T.duelRecTitle}</p>
        <p className="mt-1.5 text-base font-bold text-paper">{T.duelRecFirst}</p>
        <p className="mt-0.5 text-xs text-paper/50">{T.duelRecFirstDesc}</p>
      </div>
    );
  }

  const pct = (n: number) => `${(n / total) * 100}%`;
  return (
    <div className="rounded-card bg-white/5 px-4 py-4 ring-1 ring-white/10">
      <p className="text-center text-[11px] font-semibold uppercase tracking-[0.16em] text-paper/40">
        {T.duelRecTitle} · {T.duelRecGames(total)}
      </p>

      <div className="mt-2 flex items-end justify-center gap-4">
        <div className="min-w-0 flex-1 text-right">
          <div className="truncate text-xs font-medium text-paper/55">{youName}</div>
          <div className={`font-extrabold tabular-nums leading-none text-emerald-300 ${compact ? "text-4xl" : "text-5xl"}`}>
            {record.wins}
          </div>
        </div>
        <div className="pb-1 text-lg font-bold text-paper/30">:</div>
        <div className="min-w-0 flex-1 text-left">
          <div className="truncate text-xs font-medium text-paper/55">{themName}</div>
          <div className={`font-extrabold tabular-nums leading-none text-red-300 ${compact ? "text-4xl" : "text-5xl"}`}>
            {record.losses}
          </div>
        </div>
      </div>

      <div
        className="mt-3 flex h-2.5 overflow-hidden rounded-full bg-white/10"
        role="img"
        aria-label={T.duelRecSummary(record.wins, record.losses, record.draws)}
      >
        <div className="bg-emerald-400" style={{ width: pct(record.wins) }} />
        <div className="bg-amber-300" style={{ width: pct(record.draws) }} />
        <div className="bg-red-400" style={{ width: pct(record.losses) }} />
      </div>
      <p className="mt-1.5 text-center text-xs text-paper/50">
        {T.duelRecSummary(record.wins, record.losses, record.draws)}
      </p>

      <div className="mt-3 flex items-center justify-center gap-1.5" aria-label={T.duelRecLast}>
        {last.map((m) => (
          <span
            key={m.id}
            title={`${m.myHp} – ${m.theirHp}${m.abandoned ? ` · ${T.duelRecLeft}` : ""}`}
            className={`flex h-7 w-7 items-center justify-center rounded-full text-[11px] font-bold ring-1 ${CHIP[m.result]}`}
          >
            {LETTER[m.result]}
          </span>
        ))}
      </div>
    </div>
  );
}
