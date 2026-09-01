"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";

// One shape for every play option: same height, same anatomy, so a list of
// them reads as a list. Without an `href` it renders as inert markup rather
// than a disabled link — an anchor with nothing behind it still looks
// clickable, and some of these genuinely have nothing behind them (PvP is
// unbuilt; Monster Hunt is locked below four words).
//
// Shared by the full chooser page (/decks/review) and the dashboard's modal,
// so the two can't drift into describing the same four modes differently.
export default function ModeRow({
  href,
  icon,
  iconClass,
  title,
  desc,
  badge,
  highlight = false,
  onNavigate,
}: {
  href?: string;
  icon: React.ReactNode;
  iconClass: string;
  title: string;
  desc: string;
  badge?: string;
  highlight?: boolean;
  /**
   * Lets a modal close itself as the link is followed. Wired to Link's
   * `onNavigate`, not `onClick`: a Cmd/Ctrl-click opens the mode in a new
   * tab without leaving this one, and dismissing the dialog the user is
   * still looking at would be wrong.
   */
  onNavigate?: () => void;
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
      onNavigate={onNavigate}
      className={`hk-card hk-card-interactive group flex items-center gap-4 px-5 py-4 ${
        highlight ? "ring-2 ring-seal/20" : ""
      }`}
    >
      {body}
    </Link>
  );
}
