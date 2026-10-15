"use client";

import { supabase } from "./db";

// The browser side of Web Push reminders (0033_web_push.sql, lib/push.ts).

export const VAPID_PUBLIC_KEY = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ?? "";

export type PushSupport = "ok" | "install-first" | "unsupported";

/**
 * Whether this browser can take reminders. An iPhone or iPad can — but only
 * from the installed app (iOS 16.4+), so in Safari it's "install-first".
 */
export function pushSupport(): PushSupport {
  const ua = navigator.userAgent;
  const ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  const installed =
    window.matchMedia("(display-mode: standalone)").matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true;
  const capable = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  if (ios && !installed) return "install-first";
  return capable ? "ok" : "unsupported";
}

/** The service worker, registered here too so reminders work even in `next dev` (sw.js caches nothing there). */
async function worker(): Promise<ServiceWorkerRegistration> {
  const url = process.env.NODE_ENV === "production" ? "/sw.js" : "/sw.js?dev=1";
  await navigator.serviceWorker.register(url, { scope: "/", updateViaCache: "none" });
  return navigator.serviceWorker.ready;
}

function keyBytes(base64url: string): Uint8Array<ArrayBuffer> {
  const padded = (base64url + "=".repeat((4 - (base64url.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(padded);
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/** This browser's reminder, if it has one: its row's hour. */
export async function currentReminder(): Promise<{ hour: number } | null> {
  if (!("serviceWorker" in navigator)) return null;
  const reg = await navigator.serviceWorker.getRegistration("/");
  const sub = await reg?.pushManager.getSubscription();
  if (!sub) return null;
  const { data } = await supabase
    .from("push_subscriptions")
    .select("remind_hour")
    .eq("endpoint", sub.endpoint)
    .maybeSingle();
  return data ? { hour: data.remind_hour as number } : null;
}

/** Asks for permission, subscribes this browser and stores it. Throws "denied" when refused. */
export async function enableReminder(hour: number): Promise<void> {
  if ((await Notification.requestPermission()) !== "granted") throw new Error("denied");
  const reg = await worker();
  const sub =
    (await reg.pushManager.getSubscription()) ??
    (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(VAPID_PUBLIC_KEY) }));
  const json = sub.toJSON();
  const { error } = await supabase.from("push_subscriptions").upsert(
    { endpoint: sub.endpoint, p256dh: json.keys?.p256dh, auth: json.keys?.auth, remind_hour: hour },
    { onConflict: "endpoint" }
  );
  if (error) throw error;
}

export async function setReminderHour(hour: number): Promise<void> {
  const reg = await navigator.serviceWorker.getRegistration("/");
  const sub = await reg?.pushManager.getSubscription();
  if (!sub) return;
  const { error } = await supabase.from("push_subscriptions").update({ remind_hour: hour }).eq("endpoint", sub.endpoint);
  if (error) throw error;
}

/** Stops this browser's reminders: the row first (it's what the server reads), then the subscription. */
export async function disableReminder(): Promise<void> {
  if (!("serviceWorker" in navigator)) return;
  const reg = await navigator.serviceWorker.getRegistration("/");
  const sub = await reg?.pushManager.getSubscription();
  if (!sub) return;
  await supabase.from("push_subscriptions").delete().eq("endpoint", sub.endpoint);
  await sub.unsubscribe().catch(() => false);
}
