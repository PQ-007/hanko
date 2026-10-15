import webpush from "web-push";

// Server side of Web Push reminders (0033_web_push.sql): the VAPID setup and
// one send. Server-only — web-push signs with the private key.
//
// Configuration, all in the web app's environment (none of it is needed for
// anything else, and while it's missing the reminder card stays hidden):
//   NEXT_PUBLIC_VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY — `npx web-push generate-vapid-keys`
//   SUPABASE_SERVICE_ROLE_KEY — for push_targets(), which reads every user
//   CRON_SECRET — what the hourly pg_cron call presents (see 0033)

export interface PushTarget {
  endpoint: string;
  p256dh: string;
  auth: string;
}

export interface PushMessage {
  title: string;
  body: string;
  /** Where a tap on the notification goes. */
  url: string;
  /** Replaces an earlier notification with the same tag instead of stacking. */
  tag?: string;
}

let configured: boolean | null = null;

export function pushConfigured(): boolean {
  if (configured !== null) return configured;
  const pub = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
  const priv = process.env.VAPID_PRIVATE_KEY;
  if (!pub || !priv) return (configured = false);
  // The push services want a contact: the site itself will do.
  webpush.setVapidDetails(process.env.NEXT_PUBLIC_SITE_URL || "mailto:hanko@example.com", pub, priv);
  return (configured = true);
}

/** "sent", "gone" (the browser dropped the subscription — delete it), or "failed". */
export async function sendPush(t: PushTarget, msg: PushMessage): Promise<"sent" | "gone" | "failed"> {
  try {
    await webpush.sendNotification(
      { endpoint: t.endpoint, keys: { p256dh: t.p256dh, auth: t.auth } },
      JSON.stringify(msg),
      // A reminder nobody saw within six hours is stale.
      { TTL: 6 * 3600, urgency: "normal" }
    );
    return "sent";
  } catch (e) {
    const status = (e as { statusCode?: number }).statusCode;
    return status === 404 || status === 410 ? "gone" : "failed";
  }
}
