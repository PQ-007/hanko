"use client";

import { useEffect } from "react";

/**
 * A full-screen session (a review, a hunt, a writing lesson, a duel) on a
 * phone or tablet: the app's top bar and bottom tabs step aside so the
 * session owns the whole screen, like a native app's pushed screen. Desktop
 * keeps its header (CSS: `html[data-immersive] .hk-chrome` below lg).
 *
 * Counted, so two mounted sessions (or a quick unmount/remount) can't leave
 * the bars hidden.
 */
let count = 0;

export function useImmersive(active = true) {
  useEffect(() => {
    if (!active) return;
    count++;
    document.documentElement.dataset.immersive = "";
    return () => {
      count = Math.max(0, count - 1);
      if (count === 0) delete document.documentElement.dataset.immersive;
    };
  }, [active]);
}
