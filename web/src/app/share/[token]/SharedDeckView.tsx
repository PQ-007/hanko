"use client";

import { useMemo, useState, useSyncExternalStore } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Layers, LogIn, Plus, Swords } from "lucide-react";
import { supabase } from "../../decks/_lib/db";
import { T } from "../../decks/_lib/strings";
import { Arena } from "../../decks/review/battle/_components/BattleArena";
import { MIN_WORDS_FOR_BATTLE } from "../../decks/review/battle/_lib/quiz";
import type { SharedDeck } from "../_lib/trial";
import { trialPool, useTrialSession } from "../_lib/useTrialSession";
import TrialCards from "./TrialCards";

/**
 * The public face of a shared deck: its words, two ways to play them with no
 * account (Monster Hunt or flip cards — `?play=hunt|cards`, so the arena's own
 * "exit" link comes back here), and the way in: sign up, or for a signed-in
 * visitor, copy the deck into their library (copy_shared_deck, 0028).
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
  const canHunt = deck.words.length >= MIN_WORDS_FOR_BATTLE;

  const cta = <JoinButton token={token} signedIn={signedIn} />;
  // The trial deals with Math.random (word order, options, the monster), so
  // it renders on the client only — a server render would never match it.
  const onClient = useSyncExternalStore(noop, () => true, () => false);

  if (play === "hunt" && canHunt) return onClient ? <TrialHunt deck={deck} exitHref={here} cta={cta} /> : null;

  return (
    // App shell, like /decks: the bar stays, only the content scrolls.
    <div className="flex h-dvh flex-col overflow-hidden bg-gradient-to-b from-paper to-paper-dim text-ink">
      <header className="shrink-0 border-b border-line/70 bg-white/80 pt-[env(safe-area-inset-top)] backdrop-blur-md">
        <div className="mx-auto flex max-w-3xl items-center justify-between gap-3 px-4 py-2.5">
          <Link href={here} className="min-w-0 truncate text-sm font-semibold text-ink-soft">
            {T.sharedBy}
          </Link>
          {signedIn ? (
            <Link href="/decks" className="text-sm font-medium text-ink-soft hover:text-ink">
              {T.backToDecks}
            </Link>
          ) : (
            <Link href={`/login?next=${encodeURIComponent(here)}`} className="hk-btn hk-btn-primary px-3 py-1.5 text-sm">
              <LogIn size={14} /> {T.sharedSignUp}
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

          <div className="mt-6 grid gap-3 sm:grid-cols-2">
            <PlayCard
              href={`${here}?play=hunt`}
              disabled={!canHunt}
              icon={<Swords size={22} />}
              title={T.sharedPlayHunt}
              desc={canHunt ? T.sharedPlayHuntDesc : T.sharedHuntNeedsWords}
              primary
            />
            <PlayCard
              href={`${here}?play=cards`}
              disabled={deck.words.length === 0}
              icon={<Layers size={22} />}
              title={T.sharedPlayCards}
              desc={T.sharedPlayCardsDesc}
            />
          </div>

          <div className="mt-6 rounded-card border border-line bg-white p-4">
            <p className="text-sm text-ink-soft">{T.sharedPitch}</p>
            <div className="mt-3">{cta}</div>
          </div>

          <ul className="mt-6 divide-y divide-line-soft overflow-hidden rounded-card border border-line bg-white">
            {deck.words.map((w, i) => (
              <li key={i} className="flex items-baseline gap-3 px-4 py-2.5">
                <span className="text-lg font-bold">{w.term}</span>
                {w.reading && w.reading !== w.term && <span className="text-sm text-ink-mute">{w.reading}</span>}
                <span className="ml-auto truncate text-right text-sm text-ink-soft">
                  {[w.meaning_mn, w.meaning].filter(Boolean).join(" · ")}
                </span>
              </li>
            ))}
          </ul>
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
    primary ? "bg-seal text-paper hover:bg-seal-dark" : "border border-line bg-white hover:bg-paper-dim"
  }`;
  if (disabled) return <div className={`${cls} cursor-not-allowed opacity-50`}>{body}</div>;
  return (
    <Link href={href} className={cls}>
      {body}
    </Link>
  );
}

/** Sign up (visitor), or copy the deck into my library (signed in). */
function JoinButton({ token, signedIn }: { token: string; signedIn: boolean }) {
  const router = useRouter();
  const [state, setState] = useState<"idle" | "copying" | "done" | "failed">("idle");

  if (!signedIn) {
    return (
      <Link
        href={`/login?next=${encodeURIComponent(`/share/${token}`)}`}
        className="hk-btn hk-btn-primary w-full px-4 py-2.5 text-sm"
      >
        <LogIn size={15} /> {T.sharedSignInToCopy}
      </Link>
    );
  }

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

/** The real Monster Hunt arena, on a local trial session. */
function TrialHunt({ deck, exitHref, cta }: { deck: SharedDeck; exitHref: string; cta: React.ReactNode }) {
  const { session } = useTrialSession(deck.words);
  const pool = useMemo(() => trialPool(deck.words), [deck.words]);
  return (
    <div className="h-dvh overflow-y-auto overscroll-contain bg-gradient-to-b from-paper to-paper-dim text-ink">
      <Arena
        session={session}
        allWords={pool}
        trial={{
          exitHref,
          banner: T.sharedTrialBanner,
          resultAction: (
            <div className="flex flex-1 flex-col gap-2">
              {cta}
              <Link
                href={exitHref}
                className="hk-btn border border-white/15 bg-white/5 px-4 py-2.5 text-sm text-paper hover:bg-white/10"
              >
                {T.sharedBack}
              </Link>
            </div>
          ),
        }}
      />
    </div>
  );
}
