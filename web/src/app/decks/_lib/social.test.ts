import { test } from "node:test";
import assert from "node:assert/strict";
import { levelFor, normalizeHandle, rankFriends, xpForLevel, type FriendRow } from "./social.ts";

// Same cases as social_test.dart on mobile: one level curve, two clients.
test("levels: each costs a little more than the last", () => {
  assert.equal(levelFor(0), 1);
  assert.equal(levelFor(99), 1);
  assert.equal(levelFor(100), 2);
  assert.equal(levelFor(1600), 5);
  assert.equal(levelFor(8100), 10);
  for (let lv = 1; lv < 30; lv++) {
    assert.equal(levelFor(xpForLevel(lv)), lv);
    assert.equal(levelFor(xpForLevel(lv + 1) - 1), lv);
  }
});

test("handles: the server's format, lowercased, @ optional", () => {
  assert.equal(normalizeHandle("@Anu_92"), "anu_92");
  assert.equal(normalizeHandle("ab"), null);
  assert.equal(normalizeHandle("bad handle"), null);
  assert.equal(normalizeHandle("x".repeat(21)), null);
});

const row = (id: string, o: Partial<FriendRow>): FriendRow => ({
  user_id: id, handle: id, name: null, image: null, is_me: false, shares: true,
  elo: null, pvp_games: null, xp_total: null, xp_week: null, added_today: null,
  reviewed_today: null, words_learned: null, kanji_learned: null, recent_kanji: null,
  active_days_week: null, ...o,
});

test("the leaderboard ranks shared rows only, by the chosen measure", () => {
  const rows = [
    row("a", { xp_week: 340, xp_total: 1250, elo: 1016 }),
    row("b", { xp_week: 410, xp_total: 900, elo: 984 }),
    row("c", { shares: false }),
  ];
  assert.deepEqual(rankFriends(rows, "week").map((r) => r.user_id), ["b", "a"]);
  assert.deepEqual(rankFriends(rows, "total").map((r) => r.user_id), ["a", "b"]);
  assert.deepEqual(rankFriends(rows, "elo").map((r) => r.user_id), ["a", "b"]);
});
