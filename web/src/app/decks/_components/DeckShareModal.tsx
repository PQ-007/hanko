"use client";

import { useEffect, useState } from "react";
import { Check, Copy, Image as ImageIcon, Link2, X } from "lucide-react";
import type { DeckWithCount } from "@/lib/types";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { STORY_MAX_WORDS } from "../_lib/storyCard";
import StoryImagePanel from "./StoryImagePanel";

/**
 * Turn a deck's public link on or off (set_deck_share, 0028), copy it, and
 * make a story image that points at it. Anyone with the link can see the
 * words and play a trial on /share/<token>; nothing about the owner shows.
 */
function toShare(row: { share_token: string | null; share_expires_at: string | null } | null) {
  if (!row?.share_token || !row.share_expires_at) return null;
  return { token: row.share_token, expiresAt: new Date(row.share_expires_at).getTime() };
}

export default function DeckShareModal({ deck, onClose }: { deck: DeckWithCount; onClose: () => void }) {
  // undefined while loading; null when there's no live link.
  const [share, setShare] = useState<{ token: string; expiresAt: number } | null | undefined>(undefined);
  const [now, setNow] = useState(() => Date.now());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);
  const [copied, setCopied] = useState(false);
  const [story, setStory] = useState<{ term: string; reading: string | null; meaning: string | null }[] | null>(null);
  const [showStory, setShowStory] = useState(false);

  useEffect(() => {
    supabase
      .from("decks")
      .select("share_token, share_expires_at")
      .eq("id", deck.id)
      .single()
      .then(({ data, error }) => {
        if (error) setError(true);
        setShare(toShare(data as { share_token: string | null; share_expires_at: string | null } | null));
      });
  }, [deck.id]);

  // The countdown, and the link going dead on screen when it expires.
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 15_000);
    return () => clearInterval(id);
  }, []);
  const live = share && share.expiresAt > now ? share : null;
  const token = share === undefined ? undefined : (live?.token ?? null);
  const minutesLeft = live ? Math.max(1, Math.ceil((live.expiresAt - now) / 60_000)) : 0;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const link = token ? `${window.location.origin}/share/${token}` : null;

  async function setShared(on: boolean) {
    setBusy(true);
    setError(false);
    const { data, error } = await supabase.rpc("set_deck_share", { p_deck_id: deck.id, p_on: on });
    setBusy(false);
    if (error) {
      setError(true);
      return;
    }
    const r = data as { token: string | null; expires_at: string | null } | null;
    setShare(toShare(r && { share_token: r.token, share_expires_at: r.expires_at }));
    setNow(Date.now());
    if (!on) setShowStory(false);
  }

  async function copy() {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // Clipboard blocked — the link is on screen to copy by hand.
    }
  }

  async function openStory() {
    setShowStory(true);
    if (story) return;
    const { data } = await supabase
      .from("words")
      .select("term, reading, meaning, meaning_mn")
      .eq("deck_id", deck.id)
      .eq("deleted", false)
      .order("date_added")
      .limit(STORY_MAX_WORDS);
    setStory(
      ((data as { term: string; reading: string | null; meaning: string | null; meaning_mn: string | null }[]) ?? []).map(
        (w) => ({ term: w.term, reading: w.reading, meaning: w.meaning_mn || w.meaning })
      )
    );
  }

  return (
    <div
      onClick={onClose}
      role="dialog"
      aria-modal
      aria-label={T.shareDeckTitle}
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/40 p-4"
    >
      <div onClick={(e) => e.stopPropagation()} className="my-auto w-full max-w-md rounded-card bg-paper p-5 shadow-2xl">
        <div className="flex items-start justify-between gap-4">
          <h2 className="text-lg font-semibold text-ink">{T.shareDeckTitle}</h2>
          <button
            onClick={onClose}
            title={T.closeLabel}
            aria-label={T.closeLabel}
            className="shrink-0 rounded-control p-1 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
          >
            <X size={18} />
          </button>
        </div>
        <p className="mt-1 text-sm text-ink-soft">{T.shareDeckDesc}</p>

        {token === undefined ? (
          <p className="mt-4 text-sm text-ink-mute">…</p>
        ) : link ? (
          <>
            <p className="mt-4 flex items-center gap-1.5 text-xs font-semibold text-emerald-700">
              <Link2 size={14} /> {T.shareLinkOn}
              <span className="ml-auto font-medium text-ink-mute">{T.shareExpiresIn(minutesLeft)}</span>
            </p>
            <div className="mt-1.5 flex gap-2">
              <input
                readOnly
                value={link}
                onFocus={(e) => e.currentTarget.select()}
                className="min-w-0 flex-1 rounded-control border border-line bg-white px-3 py-2 text-xs text-ink"
              />
              <button onClick={copy} className="hk-btn hk-btn-primary shrink-0 px-3 py-2 text-sm">
                {copied ? <Check size={15} /> : <Copy size={15} />} {copied ? T.shareCopied : T.shareCopy}
              </button>
            </div>
            {showStory ? (
              <div className="mt-4">
                {story && (
                  <StoryImagePanel
                    fileName={`${deck.name.replace(/[^\p{L}\p{N}_-]+/gu, "_") || "deck"}`}
                    card={{
                      kicker: T.sharedBy,
                      heading: deck.name,
                      stats: T.storyDeckStats(deck.word_count),
                      words: story,
                      total: deck.word_count,
                      moreLabel: T.storyMore,
                      footer: link.replace(/^https?:\/\//, ""),
                    }}
                  />
                )}
              </div>
            ) : (
              <button onClick={openStory} className="hk-btn hk-btn-quiet mt-3 w-full px-4 py-2.5 text-sm">
                <ImageIcon size={15} /> {T.shareStoryImage}
              </button>
            )}
            <button
              onClick={() => setShared(false)}
              disabled={busy}
              className="mt-4 w-full text-center text-xs font-medium text-red-700 underline disabled:opacity-50"
            >
              {T.shareLinkDisable}
            </button>
            <p className="mt-1 text-center text-[11px] text-ink-mute">{T.shareLinkDisableHint}</p>
          </>
        ) : (
          <>
            <p className="mt-4 text-xs font-semibold text-ink-mute">{T.shareLinkOff}</p>
            <button
              onClick={() => setShared(true)}
              disabled={busy}
              className="hk-btn hk-btn-primary mt-2 w-full px-4 py-2.5 text-sm disabled:opacity-50"
            >
              <Link2 size={15} /> {T.shareLinkEnable}
            </button>
          </>
        )}
        {error && <p className="mt-3 text-xs text-red-700">{T.shareFailed}</p>}
      </div>
    </div>
  );
}
