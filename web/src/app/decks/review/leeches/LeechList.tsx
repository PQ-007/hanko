"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { ArrowLeft, GraduationCap, Pencil, RotateCcw } from "@/ui/icons";
import type { Word } from "@/lib/types";
import { supabase } from "../../_lib/db";
import { LEECH_LAPSES } from "../../_lib/leech";
import { T } from "../../_lib/strings";
import WordEditModal from "../../_components/WordEditModal";

interface LeechRow {
  id: string;
  lapses: number;
  suspended: boolean;
  word: Word;
}

/**
 * Hard words — the cards you keep forgetting ("leeches", Anki's word). Not a
 * drill first: seeing the same card sooner rarely fixes it, so this lists the
 * words with how often each was forgotten and offers what does help — fix
 * the word (a sharper meaning, an example sentence), drill the set as real
 * reviews (leech_cards, the session's "leech" mode), or set a hopeless one
 * aside (cards.suspended, which every queue already skips) and bring it
 * back later. Mobile's rescue screen is the drill alone.
 */
export default function LeechList() {
  const params = useSearchParams();
  const deckId = params.get("deck");
  const [rows, setRows] = useState<LeechRow[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [editing, setEditing] = useState<Word | null>(null);

  const load = useCallback(async () => {
    let q = supabase
      .from("cards")
      .select("id, lapses, suspended, word:words!inner(*)")
      .gte("lapses", LEECH_LAPSES)
      .eq("word.deleted", false)
      .order("lapses", { ascending: false });
    if (deckId) q = q.eq("word.deck_id", deckId);
    const { data, error } = await q;
    setFailed(!!error);
    setRows((data as unknown as LeechRow[]) ?? []);
  }, [deckId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the fetch's own result
    load();
  }, [load]);

  async function setSuspended(row: LeechRow, suspended: boolean) {
    setRows((rs) => rs?.map((r) => (r.id === row.id ? { ...r, suspended } : r)) ?? rs);
    const { error } = await supabase.from("cards").update({ suspended }).eq("id", row.id);
    if (error) setRows((rs) => rs?.map((r) => (r.id === row.id ? { ...r, suspended: !suspended } : r)) ?? rs);
  }

  const active = rows?.filter((r) => !r.suspended) ?? [];
  const parked = rows?.filter((r) => r.suspended) ?? [];
  const practiceHref = `/decks/practice?mode=leech${deckId ? `&deck=${deckId}` : ""}`;

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-4 px-4 py-6 sm:py-10">
      <div className="flex items-center gap-3">
        <Link href="/decks/review" aria-label={T.backToDecks} className="rounded-control p-1.5 text-ink-soft hover:bg-paper-dim">
          <ArrowLeft size={18} />
        </Link>
        <h1 className="text-2xl font-bold tracking-tight text-ink">{T.leechTitle}</h1>
      </div>
      <p className="text-sm leading-relaxed text-ink-soft">{T.leechIntro}</p>

      {rows === null ? (
        <div className="space-y-2" aria-hidden>
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-16 animate-pulse rounded-card bg-line-soft/60" />
          ))}
        </div>
      ) : failed ? (
        <p className="rounded-control border border-line bg-paper-dim px-3 py-2 text-sm text-ink-soft">{T.leechLoadFailed}</p>
      ) : active.length === 0 && parked.length === 0 ? (
        <p className="rounded-card border border-dashed border-line bg-surface p-8 text-center text-sm text-ink-soft">{T.leechNone}</p>
      ) : (
        <>
          {active.length > 0 && (
            <Link href={practiceHref} className="hk-btn hk-btn-primary self-start px-4 py-2.5 text-sm">
              <GraduationCap size={16} /> {T.leechPractice(active.length)}
            </Link>
          )}
          <ul className="flex flex-col gap-2">
            {active.map((r) => (
              <Row key={r.id} row={r}>
                <button onClick={() => setEditing(r.word)} className="hk-btn hk-btn-quiet px-3 py-1.5 text-xs">
                  <Pencil size={13} /> {T.leechFix}
                </button>
                <button
                  onClick={() => setSuspended(r, true)}
                  className="rounded-control px-2.5 py-1.5 text-xs font-medium text-ink-mute transition hover:bg-paper-dim hover:text-ink"
                >
                  {T.leechSuspend}
                </button>
              </Row>
            ))}
          </ul>
          {parked.length > 0 && (
            <section className="mt-2">
              <h2 className="text-sm font-semibold text-ink">{T.leechSuspendedTitle}</h2>
              <p className="mb-2 text-xs text-ink-mute">{T.leechSuspendedNote}</p>
              <ul className="flex flex-col gap-2 opacity-70">
                {parked.map((r) => (
                  <Row key={r.id} row={r}>
                    <button onClick={() => setSuspended(r, false)} className="hk-btn hk-btn-quiet px-3 py-1.5 text-xs">
                      <RotateCcw size={13} /> {T.leechRestore}
                    </button>
                  </Row>
                ))}
              </ul>
            </section>
          )}
        </>
      )}

      {editing && (
        <WordEditModal
          word={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            load();
          }}
        />
      )}
    </div>
  );
}

function Row({ row, children }: { row: LeechRow; children: React.ReactNode }) {
  const w = row.word;
  const meaning = [w.meaning_mn, w.meaning].filter(Boolean).join(" · ");
  return (
    <li className="hk-card flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3">
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          <span lang="ja" className="text-lg font-bold text-ink">
            {w.term}
          </span>
          {w.reading && w.reading !== w.term && <span className="text-xs text-ink-mute">{w.reading}</span>}
        </div>
        {meaning && <p className="truncate text-xs text-ink-soft">{meaning}</p>}
      </div>
      <span className="shrink-0 rounded-full bg-paper-dim px-2 py-0.5 text-[11px] font-medium tabular-nums text-ink-soft">
        {T.leechLapses(row.lapses)}
      </span>
      <div className="flex shrink-0 items-center gap-1">{children}</div>
    </li>
  );
}
