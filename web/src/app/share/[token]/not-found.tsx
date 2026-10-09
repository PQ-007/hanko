import { T } from "../../decks/_lib/strings";

export default function SharedDeckNotFound() {
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-4 bg-paper p-8 text-center text-ink">
      <p className="text-ink-soft">{T.sharedNotFound}</p>
    </main>
  );
}
