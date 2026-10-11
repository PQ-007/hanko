import { test } from "node:test";
import assert from "node:assert/strict";
import {
  acceptIncoming,
  acceptReady,
  allowMessage,
  cleanText,
  displayText,
  emotePose,
  MAX_TEXT,
  readyDeadline,
  READY_ROOM_MS,
  shouldStart,
} from "./chat.ts";

// Same cases as mobile/test/duel_chat_rules_test.dart.

const them = "u-them";
const strangers = { opponentId: them, isFriend: false };
const friends = { opponentId: them, isFriend: true };

test("emotes and phrases from the opponent are shown, by known id only", () => {
  assert.deepEqual(acceptIncoming({ v: 1, from: them, kind: "emote", id: "taunt" }, strangers), {
    v: 1,
    from: them,
    kind: "emote",
    id: "taunt",
  });
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "phrase", id: "gg" }, strangers)?.id, "gg");
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "emote", id: "nuke" }, strangers), null);
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "phrase", id: "<b>hi</b>" }, strangers), null);
});

test("typed text only between friends — a stranger's never reaches the screen", () => {
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "text", text: "hello" }, strangers), null);
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "text", text: "hello" }, friends)?.text, "hello");
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "text", text: "   " }, friends), null);
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "text", text: 42 }, friends), null);
});

test("only the opponent, only this protocol version, only objects", () => {
  assert.equal(acceptIncoming({ v: 1, from: "someone-else", kind: "emote", id: "wave" }, friends), null);
  assert.equal(acceptIncoming({ v: 2, from: them, kind: "emote", id: "wave" }, friends), null);
  assert.equal(acceptIncoming({ from: them, kind: "emote", id: "wave" }, friends), null);
  assert.equal(acceptIncoming("wave", friends), null);
  assert.equal(acceptIncoming(null, friends), null);
  // Extra fields are dropped, not passed through.
  assert.deepEqual(Object.keys(acceptIncoming({ v: 1, from: them, kind: "emote", id: "wave", html: "x" }, friends)!).sort(), [
    "from",
    "id",
    "kind",
    "v",
  ]);
});

test("typed text is cleaned: control and direction characters, whitespace, length", () => {
  assert.equal(cleanText("  hi\n\tthere  "), "hi there");
  assert.equal(cleanText("a\u202eb\u200bc"), "a b c");
  assert.equal(cleanText("x".repeat(500)).length, MAX_TEXT);
  assert.equal(acceptIncoming({ v: 1, from: them, kind: "text", text: "y".repeat(500) }, friends)?.text?.length, MAX_TEXT);
});

test("what a message reads as", () => {
  assert.equal(displayText({ v: 1, from: them, kind: "emote", id: "rip" }), "💀");
  assert.equal(displayText({ v: 1, from: them, kind: "phrase", id: "gg" }), "Сайн тоглолт!");
  assert.equal(displayText({ v: 1, from: them, kind: "text", text: "сайн уу" }), "сайн уу");
});

test("an emote plays the first pose the fighter has, else idle", () => {
  const full = ["idle", "walk", "attack01", "attack02", "attack03", "hurt", "death", "block"];
  const archer = ["idle", "walk", "attack01", "attack02", "hurt", "death"];
  const bat = ["idle", "attack01", "attack02", "hurt", "death"];
  assert.equal(emotePose(full, "taunt"), "attack03");
  assert.equal(emotePose(archer, "taunt"), "attack02");
  assert.equal(emotePose(full, "guard"), "block");
  assert.equal(emotePose(archer, "guard"), "hurt");
  assert.equal(emotePose(bat, "wave"), "idle", "a bat has no walk");
  assert.equal(emotePose(full, "unknown"), "idle");
});

test("the ready room starts on two readys, or at the shared deadline", () => {
  const started = "2026-10-11T10:00:00.000Z";
  const deadline = readyDeadline(started, 0);
  assert.equal(deadline, Date.parse(started) + READY_ROOM_MS);
  assert.equal(readyDeadline(null, 1000), 1000 + READY_ROOM_MS);
  assert.equal(readyDeadline("not a date", 1000), 1000 + READY_ROOM_MS);
  assert.equal(shouldStart(true, true, 0, deadline), true);
  assert.equal(shouldStart(true, false, deadline - 1, deadline), false);
  assert.equal(shouldStart(false, false, deadline, deadline), true, "nobody can stall it");
});

test("rate limit: four in four seconds, then room again as the window slides", () => {
  const h: number[] = [];
  assert.deepEqual([0, 100, 200, 300].map((t) => allowMessage(h, t)), [true, true, true, true]);
  assert.equal(allowMessage(h, 3999), false);
  assert.equal(allowMessage(h, 4000), true, "the first has left the window");
  assert.equal(allowMessage(h, 4001), false);
});

test("ready broadcasts: the opponent's, a real boolean, this version", () => {
  assert.equal(acceptReady({ v: 1, from: them, ready: true }, them), true);
  assert.equal(acceptReady({ v: 1, from: them, ready: false }, them), false);
  assert.equal(acceptReady({ v: 1, from: "someone-else", ready: true }, them), null);
  assert.equal(acceptReady({ v: 1, from: them, ready: "yes" }, them), null);
  assert.equal(acceptReady({ v: 2, from: them, ready: true }, them), null);
  assert.equal(acceptReady(null, them), null);
});
