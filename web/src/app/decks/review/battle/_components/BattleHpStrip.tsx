// Full-width HP strip with a centered "VS" badge, replacing the earlier
// two-separate-HpBar layout — matches the reference layout the user asked
// for. Plain CSS transition-[width] fill, same reasoning as before: NOT
// useCountUp (_lib/useAnim.ts always eases from 0, which would flash the bar
// empty on every hit instead of draining smoothly from its current value).
export default function BattleHpStrip({
  playerHp,
  monsterHp,
  maxHp,
}: {
  playerHp: number;
  monsterHp: number;
  maxHp: number;
}) {
  const playerPct = Math.max(0, Math.min(100, (playerHp / maxHp) * 100));
  const monsterPct = Math.max(0, Math.min(100, (monsterHp / maxHp) * 100));

  return (
    <div className="flex w-full items-center gap-3">
      <div className="flex-1">
        <div className="mb-1 text-right text-xs font-bold tabular-nums text-paper/70">
          {Math.max(0, Math.round(playerHp))}/{maxHp}
        </div>
        <div className="h-3.5 w-full overflow-hidden rounded-full bg-black/35 shadow-inner ring-1 ring-white/5">
          {/* Anchored to the right edge: drains from the left inward, toward
              the VS badge, mirroring the monster bar on the other side. */}
          <div
            style={{ width: `${playerPct}%`, marginLeft: `${100 - playerPct}%` }}
            className="h-full rounded-full bg-gradient-to-l from-rose-500 to-red-600 transition-[width] duration-300"
          />
        </div>
      </div>

      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-gradient-to-b from-seal to-seal-dark text-[10px] font-extrabold tracking-wider text-paper shadow-md ring-2 ring-white/15">
        VS
      </div>

      <div className="flex-1">
        <div className="mb-1 text-xs font-bold tabular-nums text-paper/70">
          {Math.max(0, Math.round(monsterHp))}/{maxHp}
        </div>
        <div className="h-3.5 w-full overflow-hidden rounded-full bg-black/35 shadow-inner ring-1 ring-white/5">
          <div
            style={{ width: `${monsterPct}%` }}
            className="h-full rounded-full bg-gradient-to-r from-rose-500 to-red-600 transition-[width] duration-300"
          />
        </div>
      </div>
    </div>
  );
}
