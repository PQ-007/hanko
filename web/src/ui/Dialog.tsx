"use client";

import { useEffect, useRef, useState } from "react";
import { T } from "@/app/decks/_lib/strings";
import Icon, { type IconName } from "./Icon";

// The app's own confirm/prompt, in place of window.confirm/prompt: those
// can't be themed (a white system box over a dark page), can't say which
// button is the destructive one, and look like a different program.
//
// Imperative on purpose — `if (!(await askConfirm(...))) return;` reads the
// same as the confirm() it replaces, with no open/close state per caller.
// One <DialogHost/> (root layout) renders whatever is asked; asks made while
// a dialog is open wait their turn.

type ConfirmOpts = {
  title: string;
  body?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Red confirm button and a warning icon — for deletes. */
  danger?: boolean;
  icon?: IconName;
};

type TextOpts = {
  title: string;
  body?: string;
  placeholder?: string;
  initial?: string;
  confirmLabel?: string;
  cancelLabel?: string;
};

type Ask =
  | { kind: "confirm"; opts: ConfirmOpts; resolve: (v: boolean) => void }
  | { kind: "text"; opts: TextOpts; resolve: (v: string | null) => void };

const queue: Ask[] = [];
let notify: (() => void) | null = null;

function push(a: Ask) {
  queue.push(a);
  notify?.();
}

export function askConfirm(opts: ConfirmOpts): Promise<boolean> {
  // No host mounted (shouldn't happen) — fall back rather than hang forever.
  if (!notify) return Promise.resolve(window.confirm([opts.title, opts.body].filter(Boolean).join("\n")));
  return new Promise((resolve) => push({ kind: "confirm", opts, resolve }));
}

/** Resolves to the trimmed text, or null when cancelled or left empty. */
export function askText(opts: TextOpts): Promise<string | null> {
  if (!notify) return Promise.resolve(window.prompt(opts.title, opts.initial ?? "")?.trim() || null);
  return new Promise((resolve) => push({ kind: "text", opts, resolve }));
}

export function DialogHost() {
  const [current, setCurrent] = useState<Ask | null>(null);
  const [text, setText] = useState("");
  const confirmRef = useRef<HTMLButtonElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const returnFocus = useRef<HTMLElement | null>(null);

  useEffect(() => {
    const pull = () =>
      setCurrent((c) => {
        if (c || queue.length === 0) return c;
        const next = queue.shift()!;
        returnFocus.current = document.activeElement as HTMLElement | null;
        setText(next.kind === "text" ? (next.opts.initial ?? "") : "");
        return next;
      });
    notify = pull;
    pull();
    return () => {
      notify = null;
    };
  }, []);

  // Done with one: answer it, give focus back, then show the next queued ask.
  function finish(answer: boolean) {
    if (!current) return;
    if (current.kind === "confirm") current.resolve(answer);
    else current.resolve(answer ? text.trim() || null : null);
    returnFocus.current?.focus?.();
    setCurrent(null);
    queueMicrotask(() => notify?.());
  }

  useEffect(() => {
    if (!current) return;
    if (current.kind === "text") inputRef.current?.select();
    else confirmRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        finish(false);
      }
    };
    // Capture phase, so Escape closes this and not a modal underneath it.
    document.addEventListener("keydown", onKey, true);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey, true);
      document.body.style.overflow = prev;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current]);

  if (!current) return null;
  const o = current.opts;
  const danger = current.kind === "confirm" && !!current.opts.danger;
  const icon: IconName | undefined =
    current.kind === "confirm" ? (current.opts.icon ?? (danger ? "trash" : undefined)) : undefined;
  const canSubmit = current.kind === "confirm" || text.trim().length > 0;

  return (
    <div
      onMouseDown={(e) => e.target === e.currentTarget && finish(false)}
      className="hk-dialog-backdrop fixed inset-0 z-[100] flex items-end justify-center bg-black/45 p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur-[2px] sm:items-center sm:p-4"
    >
      <div
        role={danger ? "alertdialog" : "dialog"}
        aria-modal
        aria-labelledby="hk-dialog-title"
        aria-describedby={o.body ? "hk-dialog-body" : undefined}
        className="hk-dialog w-full max-w-[400px] overflow-hidden rounded-card border border-line bg-surface shadow-2xl"
      >
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (canSubmit) finish(true);
          }}
          className="p-5 sm:p-6"
        >
          <div className="flex items-start gap-4">
            {icon && (
              <span
                className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-full ${
                  danger ? "bg-red-100 text-red-600 dark:text-red-300" : "bg-seal-tint text-seal"
                }`}
              >
                <Icon name={icon} size={20} />
              </span>
            )}
            <div className="min-w-0 flex-1 pt-0.5">
              <h2 id="hk-dialog-title" className="text-[17px] font-semibold leading-snug text-ink">
                {o.title}
              </h2>
              {o.body && (
                <p id="hk-dialog-body" className="mt-1.5 text-sm leading-relaxed text-ink-soft">
                  {o.body}
                </p>
              )}
            </div>
          </div>

          {current.kind === "text" && (
            <input
              ref={inputRef}
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder={current.opts.placeholder}
              className="hk-input mt-4 w-full rounded-control border border-line bg-paper px-3 py-2.5 text-sm text-ink focus:border-seal focus:ring-2 focus:ring-seal-tint"
            />
          )}

          <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <button
              type="button"
              onClick={() => finish(false)}
              className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm"
            >
              {o.cancelLabel ?? T.cancel}
            </button>
            <button
              ref={confirmRef}
              type="submit"
              disabled={!canSubmit}
              className={
                danger
                  ? "hk-btn bg-red-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-red-700 focus-visible:ring-2 focus-visible:ring-red-400 disabled:opacity-50"
                  : "hk-btn hk-btn-primary px-5 py-2.5 text-sm"
              }
            >
              {o.confirmLabel ?? (danger ? T.delete : T.ok)}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
