import type { LucideIcon } from "lucide-react";

// A single headline number with a label and icon. Value uses the font's
// default proportional figures (not tabular-nums) per the stat-tile figure
// contract — tabular alignment only matters in columns, not standalone.
export default function StatTile({
  icon: Icon,
  label,
  value,
  sub,
}: {
  icon: LucideIcon;
  label: string;
  value: string | number;
  sub?: string;
}) {
  return (
    <div className="flex items-start gap-3 rounded-lg border border-gray-200 bg-white p-4 shadow-sm">
      <div className="rounded-md bg-gray-100 p-2 text-gray-500">
        <Icon size={18} />
      </div>
      <div className="min-w-0">
        <p className="text-2xl font-semibold leading-tight text-gray-900">{value}</p>
        <p className="truncate text-xs text-gray-500">{label}</p>
        {sub && <p className="truncate text-[11px] text-gray-400">{sub}</p>}
      </div>
    </div>
  );
}
