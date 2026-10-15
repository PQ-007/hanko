import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { pushConfigured, sendPush, type PushTarget } from "@/lib/push";
import { T } from "@/app/decks/_lib/strings";

export const runtime = "nodejs";

// The hourly "N cards are due" run (0033_web_push.sql): called by pg_cron
// with CRON_SECRET, asks push_targets() who is due a reminder this hour —
// which also claims them, so an overlapping run can't double-send — and pushes
// each one. Subscriptions the push service says are gone are deleted.
//
// GET as well as POST, so a different scheduler (Vercel Cron sends GET) can
// drive it too.
async function run(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!pushConfigured() || !service) {
    return NextResponse.json({ error: "push not configured" }, { status: 503 });
  }

  const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("push_targets");
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  const targets = (data ?? []) as (PushTarget & { due_now: number })[];
  const results = await Promise.all(
    targets.map((t) =>
      sendPush(t, { title: "Hanko", body: T.pushDueBody(t.due_now), url: "/decks/review", tag: "hanko-due" })
    )
  );
  const gone = targets.filter((_, i) => results[i] === "gone").map((t) => t.endpoint);
  if (gone.length) await admin.rpc("push_drop", { p_endpoints: gone });

  return NextResponse.json({
    targets: targets.length,
    sent: results.filter((r) => r === "sent").length,
    gone: gone.length,
    failed: results.filter((r) => r === "failed").length,
  });
}

export const GET = run;
export const POST = run;
