// Duel chat — emotes, preset phrases and (between friends) typed messages, in
// the ready room before a PvP match and on the result screen after it.
//
// Transport is a Realtime broadcast on the match's own channel: nothing is
// stored, so there is no table, no history and nothing to moderate later.
// That makes the RECEIVER the one who enforces the rules, here, in
// acceptIncoming(): a client can put anything on the channel, but this side
// only shows the opponent's messages, only known emote/phrase ids, and typed
// text only when the server said the two of you are friends
// (duel_opponent().is_friend). A stranger can't make free text appear on your
// screen, however their client was modified.
//
// mobile/lib/features/duel/duel_chat_rules.dart is a port; the two tests run
// the same cases, so a phone and a browser always agree on what gets shown.

import type { SpriteState } from "../../battle/_lib/sprites";

export const CHAT_EVENT = "msg";

/**
 * "Ready" goes out twice: in presence (the state a late joiner or a reconnect
 * syncs to) and as a broadcast on this event, because presence takes a couple
 * of seconds to reach the other side — measured at 2-3 s, which left one
 * player's first round starting that much before the other's. The broadcast
 * arrives in a fraction of a second.
 */
export const READY_EVENT = "ready";
export const chatTopic = (matchId: string) => `duel-chat:${matchId}`;

/** How long the ready room waits for two "ready"s before starting anyway. */
export const READY_ROOM_MS = 30_000;

/** Typed messages are cut to this. */
export const MAX_TEXT = 120;

/** At most this many messages in RATE_WINDOW_MS, sent or shown. */
export const RATE_MAX = 4;
export const RATE_WINDOW_MS = 4_000;

export type EmoteId = "wave" | "taunt" | "cheer" | "ouch" | "guard" | "rip";

/**
 * An emote plays on the sender's own fighter: the first of `poses` that the
 * character has (packs differ — not every fighter can block or has a third
 * attack), else idle.
 */
export const EMOTES: { id: EmoteId; icon: string; poses: SpriteState[] }[] = [
  { id: "wave", icon: "👋", poses: ["walk"] },
  { id: "taunt", icon: "😤", poses: ["attack03", "attack02", "attack01"] },
  { id: "cheer", icon: "🎉", poses: ["attack01"] },
  { id: "ouch", icon: "😵", poses: ["hurt"] },
  { id: "guard", icon: "🛡️", poses: ["block", "hurt"] },
  { id: "rip", icon: "💀", poses: ["death"] },
];

export const PHRASES: { id: string; text: string }[] = [
  { id: "hi", text: "Сайн уу!" },
  { id: "gl", text: "Амжилт хүсье!" },
  { id: "gg", text: "Сайн тоглолт!" },
  { id: "wow", text: "Гоё байна!" },
  { id: "close", text: "Арай л гэж!" },
  { id: "again", text: "Дахиад нэг үү?" },
  { id: "thanks", text: "Баярлалаа!" },
];

export type ChatKind = "emote" | "phrase" | "text";

export interface ChatPayload {
  v: 1;
  from: string;
  kind: ChatKind;
  /** emote or phrase id */
  id?: string;
  /** typed text */
  text?: string;
}

/** Whitespace collapsed, control characters gone, cut to MAX_TEXT. */
export function cleanText(s: string): string {
  return (
    s
      .replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g, " ")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, MAX_TEXT)
      .trim()
  );
}

/**
 * The incoming message to show, or null. Only the opponent's; only ids this
 * client knows; typed text only from a friend, and cleaned.
 */
export function acceptIncoming(
  payload: unknown,
  opts: { opponentId: string; isFriend: boolean }
): ChatPayload | null {
  if (!payload || typeof payload !== "object") return null;
  const p = payload as Record<string, unknown>;
  if (p.v !== 1 || p.from !== opts.opponentId) return null;
  switch (p.kind) {
    case "emote":
      return EMOTES.some((e) => e.id === p.id) ? { v: 1, from: opts.opponentId, kind: "emote", id: p.id as string } : null;
    case "phrase":
      return PHRASES.some((x) => x.id === p.id) ? { v: 1, from: opts.opponentId, kind: "phrase", id: p.id as string } : null;
    case "text": {
      if (!opts.isFriend || typeof p.text !== "string") return null;
      const text = cleanText(p.text);
      return text ? { v: 1, from: opts.opponentId, kind: "text", text } : null;
    }
    default:
      return null;
  }
}

/** The opponent's ready flag from a READY_EVENT broadcast, or null if it isn't one. */
export function acceptReady(payload: unknown, opponentId: string): boolean | null {
  if (!payload || typeof payload !== "object") return null;
  const p = payload as Record<string, unknown>;
  if (p.v !== 1 || p.from !== opponentId || typeof p.ready !== "boolean") return null;
  return p.ready;
}

/** What a message reads as in the log and the speech bubble. */
export function displayText(p: ChatPayload): string {
  if (p.kind === "emote") return EMOTES.find((e) => e.id === p.id)?.icon ?? "";
  if (p.kind === "phrase") return PHRASES.find((x) => x.id === p.id)?.text ?? "";
  return p.text ?? "";
}

/** The pose an emote plays on a fighter that has the clips in `available`. */
export function emotePose(available: readonly string[], emote: string): SpriteState {
  const e = EMOTES.find((x) => x.id === emote);
  return (e?.poses.find((p) => available.includes(p)) ?? "idle") as SpriteState;
}

/**
 * When the ready room starts on its own: 30 s after the server marked the
 * match active (matches.started_at, set when the guest joined) — the same
 * moment on both screens. Without a start time, 30 s from now.
 */
export function readyDeadline(startedAt: string | null | undefined, now: number): number {
  const t = startedAt ? Date.parse(startedAt) : NaN;
  return (Number.isFinite(t) ? t : now) + READY_ROOM_MS;
}

export function shouldStart(meReady: boolean, foeReady: boolean, now: number, deadline: number): boolean {
  return (meReady && foeReady) || now >= deadline;
}

/**
 * Sliding-window rate limit: true (and the time recorded) when another
 * message fits. Used both to throttle sending and to drop a flood arriving.
 */
export function allowMessage(history: number[], now: number): boolean {
  while (history.length && now - history[0] >= RATE_WINDOW_MS) history.shift();
  if (history.length >= RATE_MAX) return false;
  history.push(now);
  return true;
}
