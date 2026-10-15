"use client";

import { useEffect, useState } from "react";
import { T } from "../_lib/strings";
import {
  currentReminder,
  disableReminder,
  enableReminder,
  pushSupport,
  setReminderHour,
  VAPID_PUBLIC_KEY,
  type PushSupport,
} from "../_lib/pushClient";

const DEFAULT_HOUR = 9; // mobile's default (core/reminders.dart)

/**
 * The daily "N cards are due" reminder for this browser (Web Push, 0033).
 * Hidden entirely until the site has push keys configured, so the settings
 * page is unchanged until reminders are switched on server-side.
 */
export default function ReminderSettings() {
  const [support, setSupport] = useState<PushSupport | null>(null);
  const [on, setOn] = useState(false);
  const [hour, setHour] = useState(DEFAULT_HOUR);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    if (!VAPID_PUBLIC_KEY) return;
    const s = pushSupport();
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reads the browser once, after mount
    setSupport(s);
    if (s !== "ok") return;
    currentReminder()
      .then((r) => {
        if (!r) return;
        setOn(true);
        setHour(r.hour);
      })
      .catch(() => {});
  }, []);

  if (!VAPID_PUBLIC_KEY || support === null) return null;

  async function toggle() {
    setBusy(true);
    setNote(null);
    try {
      if (on) {
        await disableReminder();
        setOn(false);
      } else {
        await enableReminder(hour);
        setOn(true);
      }
    } catch (e) {
      setNote(e instanceof Error && e.message === "denied" ? T.reminderDenied : T.reminderFailed);
    } finally {
      setBusy(false);
    }
  }

  async function pickHour(h: number) {
    const before = hour;
    setHour(h);
    if (!on) return;
    try {
      await setReminderHour(h);
    } catch {
      setHour(before);
      setNote(T.reminderFailed);
    }
  }

  async function test() {
    setNote(null);
    const res = await fetch("/api/push/test", { method: "POST" }).catch(() => null);
    const sent = res?.ok ? ((await res.json()).sent as number) : 0;
    setNote(sent > 0 ? T.reminderTestSent : T.reminderTestFailed);
  }

  return (
    <section className="hk-card p-5">
      <h2 className="text-base font-bold text-ink">{T.reminderTitle}</h2>
      <p className="mt-0.5 text-xs text-ink-mute">{T.reminderDesc}</p>
      <div className="mt-4">
        {support === "install-first" ? (
          <p className="text-sm text-ink-soft">{T.reminderInstallFirst}</p>
        ) : support === "unsupported" ? (
          <p className="text-sm text-ink-soft">{T.reminderUnsupported}</p>
        ) : (
          <div className="flex flex-col gap-3">
            <button
              role="switch"
              aria-checked={on}
              disabled={busy}
              onClick={toggle}
              className="flex w-full items-center justify-between gap-4 text-left disabled:opacity-60"
            >
              <span className="text-sm font-medium text-ink">{on ? T.reminderDisable : T.reminderEnable}</span>
              <span className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${on ? "bg-seal" : "bg-paper-deep"}`}>
                <span className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all ${on ? "left-[22px]" : "left-0.5"}`} />
              </span>
            </button>
            <label className="flex items-center justify-between gap-4 text-sm text-ink">
              {T.reminderHour}
              <select
                value={hour}
                onChange={(e) => pickHour(Number(e.target.value))}
                className="hk-input rounded-control border border-line bg-surface px-2 py-1.5 text-sm text-ink tabular-nums"
              >
                {Array.from({ length: 24 }, (_, h) => (
                  <option key={h} value={h}>
                    {String(h).padStart(2, "0")}:00
                  </option>
                ))}
              </select>
            </label>
            {on && (
              <button onClick={test} className="hk-btn hk-btn-quiet self-start px-3 py-1.5 text-xs">
                {T.reminderTest}
              </button>
            )}
          </div>
        )}
        {note && <p className="mt-3 text-xs text-ink-soft">{note}</p>}
      </div>
    </section>
  );
}
