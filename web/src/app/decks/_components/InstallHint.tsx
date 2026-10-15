"use client";

import { useEffect, useState } from "react";
import { X } from "@/ui/icons";
import { T } from "../_lib/strings";

const KEY = "hanko.installHint.dismissed";

/**
 * "Add to Home Screen" on an iPhone or iPad, where Safari never offers it by
 * itself — and where installing is what makes offline review dependable
 * (Safari clears a site's saved data after a week unused, but not an
 * installed app's) and what lets reminders arrive at all. Shown in Safari
 * only, never once installed, and gone for good when dismissed. Android's
 * browsers offer installing on their own.
 */
export default function InstallHint() {
  const [show, setShow] = useState(false);
  useEffect(() => {
    const ua = navigator.userAgent;
    // iPadOS reports itself as a Mac; touch gives it away.
    const ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
    const safari = /Safari/.test(ua) && !/CriOS|FxiOS|EdgiOS|OPiOS/.test(ua);
    const installed =
      window.matchMedia("(display-mode: standalone)").matches ||
      (navigator as Navigator & { standalone?: boolean }).standalone === true;
    let dismissed = false;
    try {
      dismissed = localStorage.getItem(KEY) === "1";
    } catch {}
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reads the browser once, after mount
    setShow(ios && safari && !installed && !dismissed);
  }, []);

  if (!show) return null;
  return (
    // hk-chrome: steps aside during a session, like the bars.
    <div className="hk-chrome fixed inset-x-3 bottom-[calc(4.5rem+env(safe-area-inset-bottom))] z-30 mx-auto max-w-md lg:bottom-4">
      <div className="flex items-start gap-3 rounded-card border border-line bg-surface p-3.5 shadow-lg">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-ink">{T.installTitle}</p>
          <p className="mt-1 text-xs leading-relaxed text-ink-soft">{T.installIos}</p>
        </div>
        <button
          onClick={() => {
            setShow(false);
            try {
              localStorage.setItem(KEY, "1");
            } catch {}
          }}
          aria-label={T.closeLabel}
          className="-mr-1 -mt-1 shrink-0 rounded-control p-1.5 text-ink-mute hover:bg-paper-dim hover:text-ink"
        >
          <X size={16} />
        </button>
      </div>
    </div>
  );
}
