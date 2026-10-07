"use client";

import { useCallback, useState } from "react";
import { X } from "@/ui/icons";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { useModalChrome } from "../_lib/useModal";

// Bounds must match profiles_new_per_day_check in 0023_profile_cap_bounds.sql
// — without this, a value the UI accepts could still be rejected by the
// database, which would look like a silent no-op save.
const MIN_GOAL = 0;
const MAX_GOAL = 999;

// Writes straight to profiles via the client, same RLS-permitted pattern
// EnsureTimezone.tsx already uses for timezone — no RPC needed, the
// `profiles_update_own` policy already scopes this to the caller's own row.
export default function GoalModal({
  currentGoal,
  onClose,
}: {
  currentGoal: number;
  onClose: (newGoal: number | null) => void;
}) {
  const [value, setValue] = useState(String(currentGoal));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const close = useCallback(() => onClose(null), [onClose]);
  useModalChrome(close);

  const parsed = Math.round(Number(value));
  const valid = value.trim() !== "" && Number.isFinite(parsed) && parsed >= MIN_GOAL && parsed <= MAX_GOAL;

  async function save() {
    if (!valid) return;
    setBusy(true);
    setError(null);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      setBusy(false);
      setError(T.goalSaveFailed);
      return;
    }
    const { error: updErr } = await supabase
      .from("profiles")
      .update({ new_per_day: parsed })
      .eq("id", user.id);
    setBusy(false);
    if (updErr) {
      setError(updErr.message);
      return;
    }
    onClose(parsed);
  }

  return (
    <div
      onClick={close}
      role="dialog"
      aria-modal
      aria-label={T.goalModalTitle}
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/40 p-4"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="my-auto w-full max-w-sm rounded-card bg-paper p-5 shadow-2xl"
      >
        <div className="flex items-start justify-between gap-4">
          <h2 className="text-lg font-semibold text-ink">{T.goalModalTitle}</h2>
          <button
            onClick={close}
            title={T.closeLabel}
            aria-label={T.closeLabel}
            className="shrink-0 rounded-control p-1 text-ink-mute transition hover:bg-paper-dim hover:text-ink"
          >
            <X size={18} />
          </button>
        </div>

        <p className="mt-1 text-sm text-ink-soft">{T.goalModalDesc}</p>

        <label className="mt-4 flex flex-col gap-1">
          <span className="text-xs font-medium text-ink-mute">{T.goalModalLabel}</span>
          <input
            type="number"
            min={MIN_GOAL}
            max={MAX_GOAL}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && save()}
            autoFocus
            className="w-full rounded-control border border-line bg-surface px-3 py-2 text-sm focus:border-seal focus:outline-none focus:ring-2 focus:ring-seal-tint"
          />
        </label>

        {error && (
          <p className="mt-3 rounded-control border border-line bg-paper-dim px-3 py-2 text-xs text-ink">
            {error}
          </p>
        )}

        <div className="mt-4 flex gap-2">
          <button onClick={close} className="hk-btn hk-btn-quiet px-4 py-2.5 text-sm">
            {T.cancel}
          </button>
          <button
            onClick={save}
            disabled={busy || !valid}
            className="hk-btn hk-btn-primary flex-1 px-4 py-2.5 text-sm"
          >
            {T.save}
          </button>
        </div>
      </div>
    </div>
  );
}
