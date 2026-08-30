import Link from "next/link";
import { Check, LayoutDashboard, RotateCcw } from "lucide-react";
import { T } from "../../_lib/strings";

export default function SessionComplete({ count }: { count: number }) {
  return (
    <div className="mx-auto max-w-md px-4 py-10 text-center">
      <div className="rounded-card border border-line-soft bg-white p-8 shadow-sm">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-seal text-paper">
          <Check size={26} />
        </div>
        <h2 className="mt-4 text-xl font-semibold text-ink">{T.sessionComplete}</h2>

        <div className="mt-5 rounded-card bg-paper py-4">
          <p className="text-4xl font-semibold leading-none text-ink">{count}</p>
          <p className="mt-1 text-xs text-ink-soft">{T.sessionStatWords}</p>
        </div>

        <div className="mt-6 flex flex-col gap-2">
          <Link
            href="/decks/practice"
            className="flex items-center justify-center gap-1.5 hk-btn hk-btn-primary px-4 py-2.5 text-sm"
          >
            <RotateCcw size={15} /> {T.reviewAgain}
          </Link>
          <Link
            href="/decks/stats"
            className="flex items-center justify-center gap-1.5 rounded-control border border-line px-4 py-2.5 text-sm font-medium text-ink transition hover:bg-paper-dim"
          >
            <LayoutDashboard size={15} /> {T.dashboardNav}
          </Link>
        </div>
      </div>
    </div>
  );
}
