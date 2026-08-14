"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";

const REDUCED_QUERY = "(prefers-reduced-motion: reduce)";

function subscribeReducedMotion(onChange: () => void) {
  const mq = window.matchMedia(REDUCED_QUERY);
  mq.addEventListener("change", onChange);
  return () => mq.removeEventListener("change", onChange);
}

// True when the user has asked the OS for reduced motion. Every animation in
// the dashboard checks this and snaps straight to its final value instead —
// motion is decoration, never the only way information arrives.
// useSyncExternalStore keeps this SSR-safe (server renders "not reduced")
// without a setState-in-effect round trip.
export function usePrefersReducedMotion(): boolean {
  return useSyncExternalStore(
    subscribeReducedMotion,
    () => window.matchMedia(REDUCED_QUERY).matches,
    () => false
  );
}

// Fires once when the element first scrolls into view, so charts animate as
// you reach them rather than all at once behind the fold.
export function useInView<T extends HTMLElement>(): [
  React.RefObject<T | null>,
  boolean,
] {
  const ref = useRef<T>(null);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const el = ref.current;

    // Safety net: whatever happens with the observer, reveal the content.
    // Everything gated on `inView` renders at a zero/hidden initial state,
    // so a missed callback would otherwise leave a chart permanently blank —
    // an invisible chart is far worse than an unanimated one.
    const failsafe = setTimeout(() => setInView(true), 900);

    if (!el || typeof IntersectionObserver === "undefined") {
      return () => clearTimeout(failsafe);
    }

    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setInView(true);
          io.disconnect();
        }
      },
      { threshold: 0.15 }
    );
    io.observe(el);
    return () => {
      clearTimeout(failsafe);
      io.disconnect();
    };
  }, []);

  return [ref, inView];
}

// Eases a number from 0 up to `target` once `start` goes true. Uses
// easeOutCubic so it decelerates into the final value rather than stopping
// dead. Under reduced motion it returns the target immediately.
export function useCountUp(target: number, durationMs = 900, start = true): number {
  const reduced = usePrefersReducedMotion();
  const [value, setValue] = useState(0);

  useEffect(() => {
    if (reduced || !start) return;
    let frame = 0;
    const t0 = performance.now();
    const tick = (now: number) => {
      const p = Math.min(1, (now - t0) / durationMs);
      const eased = 1 - Math.pow(1 - p, 3);
      setValue(target * eased);
      if (p < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target, durationMs, start, reduced]);

  if (reduced) return target;
  return start ? value : 0;
}
