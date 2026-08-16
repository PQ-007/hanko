"use client";

import { useEffect } from "react";
import { supabase } from "../_lib/db";

// Keeps profiles.timezone in step with the browser.
//
// The SRS day boundary is evaluated server-side in the user's timezone
// (srs_day_start, migration 0007), and nothing else in the app ever writes that
// column — left null it falls back to UTC, which for UTC+8 means the "day"
// rolls over at noon and the due counts shift under you mid-afternoon.
//
// It follows the browser rather than being a setting: an SRS day should belong
// to wherever you actually are, and there's no UI to set it by hand.
export default function EnsureTimezone({ userId }: { userId?: string }) {
  useEffect(() => {
    if (!userId) return;
    (async () => {
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
      if (!tz) return;
      const { data, error } = await supabase
        .from("profiles")
        .select("timezone")
        .eq("id", userId)
        .maybeSingle();
      // Column missing = migration 0007 not applied yet; stay quiet rather than
      // shouting at the user about schema state.
      if (error || !data || data.timezone === tz) return;
      await supabase.from("profiles").update({ timezone: tz }).eq("id", userId);
    })();
  }, [userId]);

  return null;
}
