"use client";

import { useCallback, useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Swords, X } from "@/ui/icons";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { opponentLabel, type DuelInvite } from "../review/duel/_lib/match";

// A friend's challenge (or a rematch request) wherever you are in the app.
// Realtime makes it instant; a slow poll is what makes it certain (a channel
// can connect and simply never fire). Hidden on the duel page itself, whose
// lobby lists the same invitations.

const POLL_MS = 20_000;

export default function DuelInviteToast() {
  const router = useRouter();
  const path = usePathname();
  const [invite, setInvite] = useState<DuelInvite | null>(null);
  const [dismissed, setDismissed] = useState<Set<string>>(new Set());

  const refresh = useCallback(async () => {
    if (typeof document !== "undefined" && document.hidden) return;
    const { data, error } = await supabase.rpc("duel_invites");
    if (error) return; // 0030 not applied yet: no invitations, quietly
    setInvite(((data as DuelInvite[] | null) ?? [])[0] ?? null);
  }, []);

  useEffect(() => {
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let cancelled = false;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- initial read
    void refresh();
    supabase.auth.getUser().then(({ data }) => {
      const me = data.user?.id;
      if (!me || cancelled) return;
      channel = supabase
        .channel(`invites:${me}`)
        .on("postgres_changes", { event: "*", schema: "public", table: "matches", filter: `invited_id=eq.${me}` }, () =>
          void refresh()
        )
        .subscribe();
    });
    const poll = setInterval(refresh, POLL_MS);
    const onVisible = () => !document.hidden && void refresh();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      cancelled = true;
      clearInterval(poll);
      document.removeEventListener("visibilitychange", onVisible);
      if (channel) supabase.removeChannel(channel);
    };
  }, [refresh]);

  if (!invite || dismissed.has(invite.match_id) || path?.startsWith("/decks/review/duel")) return null;
  const who = opponentLabel({ name: invite.host_name, handle: invite.host_handle }, T.multiplayerTitle);

  async function decline() {
    if (!invite) return;
    setDismissed((s) => new Set(s).add(invite.match_id));
    await supabase.rpc("decline_duel_invite", { p_match_id: invite.match_id });
    void refresh();
  }

  return (
    <div className="pointer-events-none fixed inset-x-0 top-[max(0.75rem,env(safe-area-inset-top))] z-[80] flex justify-center px-3">
      <div
        role="alert"
        className="hk-dialog pointer-events-auto flex w-full max-w-md items-center gap-3 rounded-card border border-seal bg-surface px-4 py-3 shadow-2xl"
      >
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-seal text-white">
          <Swords size={18} />
        </span>
        <p className="min-w-0 flex-1 text-sm font-semibold leading-snug text-ink">
          {invite.rematch ? T.duelRematchFrom(who) : T.duelInviteFrom(who)}
        </p>
        <button
          onClick={() => router.push(`/decks/review/duel?accept=${invite.match_id}`)}
          className="hk-btn hk-btn-primary shrink-0 px-3 py-2 text-xs"
        >
          {T.duelInviteAccept}
        </button>
        <button
          onClick={decline}
          aria-label={T.duelInviteDecline}
          title={T.duelInviteDecline}
          className="shrink-0 rounded-control p-1.5 text-ink-mute hover:bg-paper-dim hover:text-ink"
        >
          <X size={16} />
        </button>
      </div>
    </div>
  );
}
