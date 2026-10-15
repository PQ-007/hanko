import { NextResponse } from "next/server";
import { clientForRequest } from "@/lib/supabase/bearer";
import { pushConfigured, sendPush, type PushTarget } from "@/lib/push";
import { T } from "@/app/decks/_lib/strings";

export const runtime = "nodejs";

// "Send a test" from the reminder settings: pushes to the caller's own
// subscriptions only — read with their session, so RLS scopes it — which
// proves the whole path (permission, subscription, keys, service worker)
// without waiting for the hour. No service-role key involved.
export async function POST(request: Request) {
  if (!pushConfigured()) return NextResponse.json({ error: "push not configured" }, { status: 503 });
  const supabase = await clientForRequest(request);
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { data, error } = await supabase.from("push_subscriptions").select("endpoint, p256dh, auth");
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  const results = await Promise.all(
    ((data ?? []) as PushTarget[]).map((t) =>
      sendPush(t, { title: "Hanko", body: T.pushTestBody, url: "/decks/settings", tag: "hanko-test" })
    )
  );
  return NextResponse.json({ sent: results.filter((r) => r === "sent").length, of: results.length });
}
