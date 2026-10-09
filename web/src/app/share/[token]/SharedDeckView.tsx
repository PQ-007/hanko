"use client";

import { useState, useSyncExternalStore } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Layers, Plus } from "@/ui/icons";
import { supabase } from "../../decks/_lib/db";
import { T } from "../../decks/_lib/strings";
import type { SharedDeck } from "../_lib/trial";
import TrialCards from "./TrialCards";

/**
 * The public face of a shared deck: its words and one way to practise them
 * with no account — flip cards (`?play=cards`). No sign-up pitch (owner's
 * call); a visitor who already has an account and is signed in can copy the
 * deck into their library (copy_shared_deck, 0028), and that's all.
 */
export default function SharedDeckView({
  deck,
  token,
  signedIn,
}: {
  deck: SharedDeck;
  token: string;
  signedIn: boolean;
}) {
  const play = useSearchParams().get("play");
  const here = `/share/${token}`;

  const cta = signedIn ? <CopyButton token={token} /> : null;
  // The trial shuffles with Math.random, so it renders on the client only —
  // a server render would never match it.
  const onClient = useSyncExternalStore(noop, () => true, () => false);

  return (
    // App shell, like /decks: the bar stays, only the content scrolls.
    <div className="flex h-dvh flex-col overflow-hidden bg-gradient-to-b from-paper to-paper-dim text-ink">
      <header className="shrink-0 border-b border-line/70 bg-surface/80 pt-[env(safe-area-inset-top)] backdrop-blur-md">
        <div className="mx-auto flex max-w-3xl items-center justify-between gap-3 px-4 py-2.5">
          <Link href={here} className="min-w-0 truncate text-sm font-semibold text-ink-soft">
            {T.sharedBy}
          </Link>
          {signedIn && (
            <Link href="/decks" className="text-sm font-medium text-ink-soft hover:text-ink">
              {T.backToDecks}
            </Link>
          )}
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
      {play === "cards" ? (
        onClient && <TrialCards words={deck.words} exitHref={here} cta={cta} />
      ) : (
        <main className="mx-auto w-full max-w-3xl px-4 py-6 pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:py-8">
          <p className="text-xs font-bold uppercase tracking-wider text-seal">{T.sharedBy}</p>
          <h1 className="mt-1 text-3xl font-extrabold tracking-tight sm:text-4xl">{deck.name}</h1>
          <p className="mt-1 text-sm text-ink-soft">{T.sharedWords(deck.words.length)}</p>

          <div className="mt-6">
            <PlayCard
              href={`${here}?play=cards`}
              disabled={deck.words.length === 0}
              icon={<Layers size={22} />}
              title={T.sharedPlayCards}
              desc={T.sharedPlayCardsDesc}
              primary
            />
          </div>

          {cta && <div className="mt-3">{cta}</div>}

          {/* The same flip cards as the owner's deck view (WordRow's grid), minus
              the grade and the edit buttons: hover, tap or focus turns a card. */}
          <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-3">
            {deck.words.map((w, i) => (
              <div key={i} tabIndex={0} className="hk-flip h-40 outline-none sm:h-44" aria-label={w.term}>
                <div className="hk-flip-inner">
                  <div className="hk-flip-face flex flex-col items-center justify-center border border-line-soft bg-surface p-4 text-center">
                    <div className="break-words text-2xl font-bold leading-tight text-ink sm:text-3xl">{w.term}</div>
                    {w.reading && w.reading !== w.term && <div className="mt-1.5 text-sm text-ink-mute">{w.reading}</div>}
                  </div>
                  <div className="hk-flip-face hk-flip-back flex flex-col items-center justify-center border border-line bg-paper p-4 text-center">
                    <div className="max-w-full truncate text-lg font-bold leading-tight text-ink">{w.term}</div>
                    {w.reading && w.reading !== w.term && <div className="max-w-full truncate text-xs text-ink-mute">{w.reading}</div>}
                    {w.meaning_mn && (
                      <div className="mt-2 line-clamp-2 break-words text-sm font-semibold leading-snug text-ink">{w.meaning_mn}</div>
                    )}
                    {w.meaning && <div className="mt-1 line-clamp-2 break-words text-xs leading-snug text-ink-mute">{w.meaning}</div>}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </main>
      )}
      </div>
    </div>
  );
}

const noop = () => () => {};

function PlayCard({
  href,
  disabled,
  icon,
  title,
  desc,
  primary = false,
}: {
  href: string;
  disabled: boolean;
  icon: React.ReactNode;
  title: string;
  desc: string;
  primary?: boolean;
}) {
  const body = (
    <>
      <span className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-control ${primary ? "bg-white/15" : "bg-seal-tint text-seal"}`}>
        {icon}
      </span>
      <span className="flex flex-col">
        <span className="font-bold">{title}</span>
        <span className={`text-xs ${primary ? "text-paper/75" : "text-ink-mute"}`}>{desc}</span>
      </span>
    </>
  );
  const cls = `flex items-center gap-3 rounded-card p-4 text-left transition ${
    primary ? "bg-seal text-paper hover:bg-seal-dark" : "border border-line bg-surface hover:bg-paper-dim"
  }`;
  if (disabled) return <div className={`${cls} cursor-not-allowed opacity-50`}>{body}</div>;
  return (
    <Link href={href} className={cls}>
      {body}
    </Link>
  );
}

/** Copy the deck into my library — shown to signed-in visitors only. */
function CopyButton({ token }: { token: string }) {
  const router = useRouter();
  const [state, setState] = useState<"idle" | "copying" | "done" | "failed">("idle");

  async function copy() {
    setState("copying");
    const { error } = await supabase.rpc("copy_shared_deck", { p_token: token });
    setState(error ? "failed" : "done");
  }

  if (state === "done") {
    return (
      <button onClick={() => router.push("/decks")} className="hk-btn w-full bg-emerald-600 px-4 py-2.5 text-sm text-white hover:bg-emerald-700">
        {T.sharedCopied}
      </button>
    );
  }
  return (
    <div className="flex flex-col gap-1">
      <button
        onClick={copy}
        disabled={state === "copying"}
        className="hk-btn hk-btn-primary w-full px-4 py-2.5 text-sm disabled:opacity-60"
      >
        <Plus size={15} /> {state === "copying" ? T.sharedCopying : T.sharedCopy}
      </button>
      {state === "failed" && <p className="text-center text-xs text-red-700">{T.sharedCopyFailed}</p>}
    </div>
  );
}
