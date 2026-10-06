import Link from "next/link";
import { T } from "../../decks/_lib/strings";

export default function SharedDeckNotFound() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 bg-paper p-8 text-center text-ink">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/hanko.svg" alt="" className="h-12 w-12" />
      <p className="text-ink-soft">{T.sharedNotFound}</p>
      <Link href="/login" className="hk-btn hk-btn-primary px-5 py-2.5 text-sm">
        {T.sharedSignUp}
      </Link>
    </main>
  );
}
