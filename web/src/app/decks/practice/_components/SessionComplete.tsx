import Link from "next/link";
import { Check, LayoutDashboard, RotateCcw } from "lucide-react";
import { T } from "../../_lib/strings";

export default function SessionComplete({ count }: { count: number }) {
  return (
    <div className="mx-auto max-w-md px-4 py-10 text-center">
      <div className="rounded-2xl border border-gray-200 bg-white p-8 shadow-sm">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-gray-900 text-white">
          <Check size={26} />
        </div>
        <h2 className="mt-4 text-xl font-semibold text-gray-900">{T.sessionComplete}</h2>

        <div className="mt-5 rounded-xl bg-gray-50 py-4">
          <p className="text-4xl font-semibold leading-none text-gray-900">{count}</p>
          <p className="mt-1 text-xs text-gray-500">{T.sessionStatWords}</p>
        </div>

        <div className="mt-6 flex flex-col gap-2">
          <Link
            href="/decks/practice"
            className="flex items-center justify-center gap-1.5 rounded-lg bg-gray-900 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-gray-800"
          >
            <RotateCcw size={15} /> {T.reviewAgain}
          </Link>
          <Link
            href="/decks/stats"
            className="flex items-center justify-center gap-1.5 rounded-lg border border-gray-300 px-4 py-2.5 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
          >
            <LayoutDashboard size={15} /> {T.dashboardNav}
          </Link>
        </div>
      </div>
    </div>
  );
}
