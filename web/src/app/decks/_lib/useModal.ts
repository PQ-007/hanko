"use client";

import { useEffect } from "react";

// Escape closes, and the page behind stops scrolling while a dialog is open.
//
// One definition rather than one copy per modal: the two behaviours have to
// arrive together (a dialog you can't dismiss with Escape, or one that lets
// the page scroll away underneath it, is broken in a way that is easy to ship
// and hard to notice), and the cleanup has to undo the overflow lock on every
// path out — including an unmount that isn't a close.
export function useModalChrome(onClose: () => void) {
  useEffect(() => {
    // Not mid-IME-composition: there Escape cancels the conversion, and
    // closing the dialog would take the half-typed Japanese with it.
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && !e.isComposing && onClose();
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [onClose]);
}
