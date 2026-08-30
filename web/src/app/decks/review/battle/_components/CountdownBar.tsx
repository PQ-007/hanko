// Kahoot-style countdown. Purely presentational now — it draws whatever
// `remainingMs` it is handed. The clock itself lives in useQuestionClock, so
// the bar, the seconds readout and the deadline that auto-answers a miss are
// all the same clock and can all be paused together.
export default function CountdownBar({
  durationMs,
  remainingMs,
  paused,
}: {
  durationMs: number;
  remainingMs: number;
  paused: boolean;
}) {
  const pct = Math.max(0, Math.min(100, (remainingMs / durationMs) * 100));
  const seconds = Math.ceil(remainingMs / 1000);
  // Last third of the clock turns red — the same third that grades "hard"
  // in BattleArena, so the colour change doubles as a hint that a correct
  // answer from here on is worth less damage.
  const low = pct <= 100 / 3;

  return (
    <div className="flex items-center gap-2">
      <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-black/10">
        <div
          className={`h-full rounded-full transition-[width] duration-100 ease-linear ${
            paused ? "bg-ink-mute" : low ? "bg-red-500" : "bg-amber-500"
          }`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span
        className={`w-5 text-right text-xs font-bold tabular-nums ${
          paused ? "text-ink-mute" : low ? "text-red-600" : "text-ink-soft"
        }`}
      >
        {seconds}
      </span>
    </div>
  );
}
