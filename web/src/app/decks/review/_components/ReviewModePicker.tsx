"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowRight, Check, Dumbbell, GraduationCap, Layers, Lock, Swords, Users } from "lucide-react";
import { supabase } from "../../_lib/db";
import { T } from "../../_lib/strings";
import { MIN_WORDS_FOR_BATTLE } from "../battle/_lib/quiz";
import { PLAYER_ROSTER } from "../battle/_lib/monsters";
import { usePlayerCharacter, writePlayerCharacter } from "../battle/_lib/playerCharacter";
import { CHARACTER_NAMES } from "../battle/_lib/sprites";
import FightScene from "../battle/_components/FightScene";
// Still used by the hero chips: those are portraits for picking a character,
// and a portrait is exactly where an idle pose belongs.
import FighterSprite from "../battle/_components/FighterSprite";

interface DeckOption {
  id: string;
  name: string;
}

// Same shape StatsDashboard reads. due_now is what a session started right now
// would actually serve; review_due/new_due ignore the daily caps, and
// due_now = least(review_due, review_remaining) + least(new_due, new_remaining)
// (0012_due_summary_at.sql). The breakdown below applies those same two
// least()s so its two halves always add up to the headline.
interface DueSummary {
  due_now: number;
  review_due: number;
  new_due: number;
  review_remaining: number;
  new_remaining: number;
}

// One shape for every play option below the Monster Hunt panel: same height,
// same anatomy, so the list reads as a list. Without an `href` it renders as
// inert markup rather than a disabled link — an anchor with nothing behind it
// still looks clickable, and PvP genuinely has nothing behind it.
function ModeRow({
  href,
  icon,
  iconClass,
  title,
  desc,
  badge,
  highlight = false,
}: {
  href?: string;
  icon: React.ReactNode;
  iconClass: string;
  title: string;
  desc: string;
  badge?: string;
  highlight?: boolean;
}) {
  const body = (
    <>
      <span
        className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-control ${iconClass}`}
      >
        {icon}
      </span>
      <div className="min-w-0 flex-1">
        <h2
          className={`flex flex-wrap items-center gap-2 text-sm font-semibold ${
            badge ? "text-ink-soft" : "text-ink"
          }`}
        >
          {title}
          {badge && (
            <span className="rounded-full bg-paper-deep px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-ink-mute">
              {badge}
            </span>
          )}
        </h2>
        <p className="text-xs leading-relaxed text-ink-mute">{desc}</p>
      </div>
      {href && (
        <ArrowRight
          size={16}
          className="shrink-0 text-ink-mute transition-transform group-hover:translate-x-1"
        />
      )}
    </>
  );

  if (!href) {
    return (
      <div
        aria-disabled
        className="flex items-center gap-4 rounded-card border border-dashed border-line bg-white/40 px-5 py-4"
      >
        {body}
      </div>
    );
  }

  return (
    <Link
      href={href}
      className={`hk-card hk-card-interactive group flex items-center gap-4 px-5 py-4 ${
        highlight ? "ring-2 ring-seal/20" : ""
      }`}
    >
      {body}
    </Link>
  );
}

function Points({ items, tone }: { items: readonly string[]; tone: string }) {
  return (
    <ul className="flex flex-col gap-1.5 text-sm">
      {items.map((p) => (
        <li key={p} className="flex items-center gap-2">
          <Check size={14} className={`shrink-0 ${tone}`} />
          {p}
        </li>
      ))}
    </ul>
  );
}

export default function ReviewModePicker() {
  const [decks, setDecks] = useState<DeckOption[]>([]);
  const [deckId, setDeckId] = useState<string | null>(null);
  // Stored with the deck it was fetched for, rather than as a bare summary
  // that gets reset to null when the scope changes. Same effect (the headline
  // falls back to its skeleton while a new scope is in flight) without an
  // imperative reset inside the effect, and it makes a late response for a
  // deck you already navigated away from unusable by construction.
  const [dueFor, setDueFor] = useState<{ deckId: string | null; summary: DueSummary | null } | null>(
    null
  );
  const [wordCount, setWordCount] = useState<number | null>(null);
  // Shared with the arena through localStorage, so the fighter in the card
  // below is the one you'll actually walk in with.
  const hero = usePlayerCharacter();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [decksRes, wordsRes] = await Promise.all([
        supabase.from("decks").select("id, name").eq("deleted", false).order("name"),
        // Head request — this only gates the Monster Hunt card (it needs 4
        // words to build 4 options), so the rows themselves are never needed.
        supabase.from("words").select("id", { count: "exact", head: true }).eq("deleted", false),
      ]);
      if (cancelled) return;
      setDecks((decksRes.data as DeckOption[]) ?? []);
      setWordCount(wordsRes.count ?? 0);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Re-runs when the deck scope changes: due_summary takes a deck id, so the
  // headline is the count for whatever is actually selected rather than a
  // whole-library number that wouldn't match the session you're about to start.
  useEffect(() => {
    let cancelled = false;
    supabase.rpc("due_summary", { p_deck_id: deckId }).then(({ data, error }) => {
      if (cancelled) return;
      const rows = data as DueSummary[] | null;
      setDueFor({ deckId, summary: error ? null : (rows?.[0] ?? null) });
    });
    return () => {
      cancelled = true;
    };
  }, [deckId]);

  function withDeck(href: string) {
    if (!deckId) return href;
    return `${href}${href.includes("?") ? "&" : "?"}deck=${deckId}`;
  }

  // Three states, not two. A failed due_summary() must not look like a
  // still-loading one (the skeleton would spin forever) and must not look like
  // a finished day either — that would promote free practice on what might be
  // a full queue. It degrades to the plain "which mode?" question instead.
  const resolved = dueFor && dueFor.deckId === deckId ? dueFor : null;
  const due = resolved?.summary ?? null;
  const loadingDue = resolved === null;
  const dueUnavailable = resolved !== null && resolved.summary === null;
  const dueNow = due?.due_now ?? 0;
  const nothingDue = due !== null && dueNow === 0;
  const heldBack = due ? due.review_due + due.new_due - due.due_now : 0;
  const battleLocked = wordCount !== null && wordCount < MIN_WORDS_FOR_BATTLE;

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-8 sm:py-12 xl:max-w-6xl">
      {/* Lead with the number, not with the question. Which mode you want is a
          taste choice; whether anything is due decides whether two of these
          three options do anything at all. */}
      <header className="flex flex-col items-center gap-3 text-center">
        <span className="rounded-full bg-seal-tint px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-seal">
          {T.practiceKicker}
        </span>
        <h1 className="text-3xl font-extrabold tracking-tight text-ink sm:text-4xl">
          {loadingDue ? (
            <span className="inline-block h-9 w-64 max-w-full animate-pulse rounded-control bg-paper-deep align-middle" />
          ) : dueUnavailable ? (
            T.chooseModeTitle
          ) : nothingDue ? (
            T.practiceNothingDue
          ) : (
            T.practiceDueHeadline(dueNow)
          )}
        </h1>
        <p className="max-w-md text-sm leading-relaxed text-ink-soft">
          {due === null
            ? " "
            : nothingDue
              ? T.practiceNothingDueSub
              : T.practiceDueBreakdown(
                  Math.min(due.review_due, due.review_remaining),
                  Math.min(due.new_due, due.new_remaining)
                )}
        </p>
        {heldBack > 0 && (
          <p className="text-xs text-ink-mute">{T.dueHeldBack(heldBack)}</p>
        )}
      </header>

      {/* Deck scope. Both session routes already accepted ?deck= — there was
          simply no way to reach that from here, so the chooser could only ever
          start an all-decks session. */}
      {decks.length > 1 && (
        <div
          role="group"
          aria-label={T.practiceScopeLabel}
          className="mt-7 flex items-center gap-2 overflow-x-auto pb-1"
        >
          <Layers size={14} className="shrink-0 text-ink-mute" />
          {[{ id: null, name: T.practiceScopeAll }, ...decks].map((d) => {
            const active = d.id === deckId;
            return (
              <button
                key={d.id ?? "all"}
                onClick={() => setDeckId(d.id)}
                aria-pressed={active}
                className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-medium transition ${
                  active
                    ? "bg-seal text-paper"
                    : "border border-line bg-white text-ink-soft hover:bg-paper-dim"
                }`}
              >
                {d.name}
              </button>
            );
          })}
        </div>
      )}

      {/* Two columns at lg: what you can play on the left, the fight itself on
          the right. The stage used to sit on top of the Monster Hunt panel,
          which pushed every other option below the fold and made the page a
          scroll rather than a choice. Side by side, the whole menu is visible
          at once and the art still has room to be big.

          DOM order puts the stage first so a phone leads with the art and
          then lists the options; the grid placement flips them at lg. */}
      <div className="mt-6 grid gap-4 lg:grid-cols-[400px_minmax(0,1fr)] lg:items-start lg:gap-6">
        {/* The stage. Sticky on desktop so the fight stays in view while the
            list is read. */}
        <section className="hk-arena overflow-hidden lg:sticky lg:top-20 lg:col-start-2 lg:row-start-1">
          {/* A fight, not a pair of idling sprites. Your chosen hero fights
              here — and wins, since this is the mode you're being offered. */}
          <div className="flex h-[170px] items-center justify-center sm:h-[210px] lg:h-[250px] xl:h-[290px]">
            <FightScene
              hero={hero}
              slotClass="hanko-fighter-slot-card"
              gapClass="gap-4 lg:gap-6"
              heroWins
            />
          </div>

          {/* The roster picker belongs to the stage, not the menu: it changes
              who is fighting directly above it, and that live feedback is the
              whole reason it reads without an explanatory label. Chips are
              restyled for the dark ground — the light-card versions were nine
              white boxes on near-black. */}
          <div className="border-t border-white/10 px-5 py-4">
            <div className="flex flex-col items-center gap-0.5 text-center">
              <h3 className="text-sm font-semibold text-paper">{T.heroPickerTitle}</h3>
              <p className="text-xs text-paper/50">{T.heroPickerHint}</p>
            </div>
            <div
              role="radiogroup"
              aria-label={T.heroPickerTitle}
              className="mt-3 flex flex-wrap justify-center gap-1.5"
            >
              {PLAYER_ROSTER.map((slug) => {
                const active = slug === hero;
                return (
                  <button
                    key={slug}
                    role="radio"
                    aria-checked={active}
                    title={CHARACTER_NAMES[slug] ?? slug}
                    onClick={() => writePlayerCharacter(slug)}
                    className={`hanko-hero-chip flex items-center justify-center rounded-control border transition ${
                      active
                        ? "border-seal bg-seal/25"
                        : "border-white/10 bg-white/5 hover:bg-white/10"
                    }`}
                  >
                    <FighterSprite slug={slug} state="idle" />
                  </button>
                );
              })}
            </div>
          </div>
        </section>

        {/* The menu. Most substantial first: Monster Hunt is the mode with
            something to show, Classic is last because it is the fallback, not
            the headline. */}
        <div className="flex flex-col gap-3 lg:col-start-1 lg:row-start-1">
          {/* 1 — Monster Hunt. The only entry that keeps a full card: it is
              the flagship, and the one whose rules are worth stating before
              you commit ten seconds a question to them. */}
          <div className={`hk-card overflow-hidden ${battleLocked ? "opacity-60" : ""}`}>
            <div className="flex items-center gap-3 border-b border-line-soft bg-seal-tint/60 px-5 py-4">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-control bg-seal text-paper">
                <Swords size={19} />
              </span>
              <div className="min-w-0">
                <h2 className="text-sm font-semibold text-ink">{T.battleModeTitle}</h2>
                <p className="text-xs leading-relaxed text-ink-mute">
                  {T.battleModeDesc}
                </p>
              </div>
            </div>
            <div className="px-5 py-4 text-ink-soft">
              <Points items={T.battlePoints} tone="text-seal" />
            </div>
            <div className="border-t border-line-soft p-4">
              {battleLocked ? (
                <p className="flex items-center justify-center gap-2 py-2 text-xs font-medium text-ink-mute">
                  <Lock size={13} />
                  {T.battleLocked(MIN_WORDS_FOR_BATTLE)}
                </p>
              ) : (
                <Link
                  href={withDeck("/decks/review/battle")}
                  className="hk-btn hk-btn-primary group w-full px-4 py-3 text-sm"
                >
                  {T.practiceStart}
                  <ArrowRight
                    size={16}
                    className="transition-transform group-hover:translate-x-1"
                  />
                </Link>
              )}
            </div>
          </div>

          {/* 2 — Free practice. The only option that still does something on a
              finished day, so that's the one day it gets promoted. */}
          <ModeRow
            href={withDeck("/decks/review/battle?mode=free")}
            icon={<Dumbbell size={19} />}
            iconClass="bg-sky-50 text-sky-700 ring-1 ring-sky-100"
            title={T.freeModeTitle}
            desc={T.freeModeDesc}
            highlight={nothingDue}
          />

          {/* 3 — PvP. Not a link and not a button: nothing is built behind
              this yet (CLAUDE.md's Phase 3.2). It is listed so the mode is
              visible, and labelled as unbuilt rather than dressed up as
              something that might respond to a click. */}
          <ModeRow
            icon={<Users size={19} />}
            iconClass="bg-paper-dim text-ink-mute"
            title={T.multiplayerTitle}
            desc={T.multiplayerDesc}
            badge={T.comingSoon}
          />

          {/* 4 — Classic. */}
          <ModeRow
            href={withDeck("/decks/practice")}
            icon={<GraduationCap size={19} />}
            iconClass="bg-paper-dim text-ink ring-1 ring-line-soft"
            title={T.classicModeTitle}
            desc={T.classicModeDesc}
          />
        </div>
      </div>
    </div>
  );
}
