"use client";

import type { LucideIcon } from "lucide-react";
import { useCountUp, useInView } from "../_lib/useAnim";

// A single headline number with a label and icon. Numeric values count up on
// first view; string values (already formatted) are shown as-is. The value
// uses the font's default proportional figures per the stat-tile contract —
// tabular alignment only matters in columns, not standalone.
export default function StatTile({
  icon: Icon,
  label,
  value,
  sub,
  suffix,
}: {
  icon: LucideIcon;
  label: string;
  value: number;
  sub?: string;
  suffix?: string;
}) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const animated = useCountUp(value, 900, inView);

  return (
    <div
      ref={ref}
      className="group flex items-start gap-3 hk-card hk-card-interactive p-4"
    >
      <div className="rounded-control bg-paper-dim p-2 text-ink-soft transition group-hover:bg-seal group-hover:text-white">
        <Icon size={18} />
      </div>
      <div className="min-w-0">
        <p className="text-2xl font-semibold leading-tight text-ink">
          {Math.round(animated).toLocaleString("en-US")}
          {suffix}
        </p>
        <p className="truncate text-xs text-ink-soft">{label}</p>
        {sub && <p className="truncate text-[11px] text-ink-mute">{sub}</p>}
      </div>
    </div>
  );
}
