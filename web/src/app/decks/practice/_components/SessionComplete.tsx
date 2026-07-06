import Link from "next/link";
import { T } from "../../_lib/strings";

export default function SessionComplete({ count }: { count: number }) {
  return (
    <div className="mx-auto max-w-md p-8 text-center">
      <div className="rounded-lg border border-gray-200 bg-white p-10 shadow-sm">
        <h2 className="text-xl font-semibold text-gray-900">{T.sessionComplete}</h2>
        <p className="mt-2 text-sm text-gray-500">{T.sessionCompleteDesc(count)}</p>
        <Link
          href="/decks"
          className="mt-6 inline-block rounded bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-800"
        >
          {T.backToDecks}
        </Link>
      </div>
    </div>
  );
}
