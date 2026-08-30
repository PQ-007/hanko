"use client";

import { ACCENT_DARK } from "../_lib/chartColors";
import { useCountUp, useInView } from "../_lib/useAnim";

// Radial progress meter. The unfilled track is a light step of the same ramp
// as the fill, so the remaining share reads as "not yet" rather than as a
// second category. The percentage is always printed in the middle, so the
// arc is reinforcement rather than the only channel.
export default function ProgressRing({
  pct,
  label,
  size = 132,
  stroke = 11,
}: {
  pct: number;
  label: string;
  size?: number;
  stroke?: number;
}) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const animated = useCountUp(pct, 1100, inView);

  const r = (size - stroke) / 2;
  const circumference = 2 * Math.PI * r;
  const offset = circumference * (1 - Math.min(100, Math.max(0, animated)) / 100);

  return (
    <div ref={ref} className="flex flex-col items-center gap-1">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="-rotate-90">
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke="#dbe7f7"
            strokeWidth={stroke}
          />
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke={ACCENT_DARK}
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={offset}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-2xl font-semibold text-ink">
            {Math.round(animated)}%
          </span>
        </div>
      </div>
      <p className="text-xs text-ink-soft">{label}</p>
    </div>
  );
}
