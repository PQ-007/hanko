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
      className="group flex items-start gap-3 rounded-lg border border-gray-200 bg-white p-4 shadow-sm transition duration-200 hover:-translate-y-0.5 hover:border-gray-300 hover:shadow-md"
    >
      <div className="rounded-md bg-gray-100 p-2 text-gray-500 transition group-hover:bg-gray-900 group-hover:text-white">
        <Icon size={18} />
      </div>
      <div className="min-w-0">
        <p className="text-2xl font-semibold leading-tight text-gray-900">
          {Math.round(animated).toLocaleString("en-US")}
          {suffix}
        </p>
        <p className="truncate text-xs text-gray-500">{label}</p>
        {sub && <p className="truncate text-[11px] text-gray-400">{sub}</p>}
      </div>
    </div>
  );
}
