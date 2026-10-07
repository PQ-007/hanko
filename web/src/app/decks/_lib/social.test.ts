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

test("head-to-head: results, perspective, ordering and what doesn't count", async () => {
  const { headToHead, totalRecord } = await import("./social.ts");
  const me = "me", a = "a", b = "b";
  const m = (id: string, host: string, guest: string | null, winner: string | null, status: string, at: string, hostHp = 50, guestHp = 0) => ({
    id, host_id: host, guest_id: guest, host_hp: hostHp, guest_hp: guestHp, winner_id: winner, status, finished_at: at, created_at: at,
  });
  const h = headToHead(
    [
      m("1", me, a, me, "finished", "2026-10-01T10:00:00Z", 64, 0),
      m("2", a, me, a, "finished", "2026-10-03T10:00:00Z", 30, 0), // I was the guest and lost
      m("3", me, a, null, "finished", "2026-10-02T10:00:00Z", 0, 0), // draw
      m("4", b, me, me, "abandoned", "2026-10-04T10:00:00Z", 100, 80), // b left; I won
      m("5", me, a, null, "active", "2026-10-05T10:00:00Z"), // live — ignored
      m("6", me, null, null, "lobby", "2026-10-05T10:00:00Z"), // nobody joined — ignored
    ],
    me
  );
  const ra = h.get(a)!;
  assert.deepEqual([ra.wins, ra.losses, ra.draws], [1, 1, 1]);
  assert.deepEqual(ra.matches.map((x) => x.id), ["2", "3", "1"], "newest first");
  assert.deepEqual([ra.matches[0].myHp, ra.matches[0].theirHp], [0, 30], "HP from my side as guest");
  const rb = h.get(b)!;
  assert.deepEqual([rb.wins, rb.matches[0].abandoned], [1, true]);
  assert.deepEqual(totalRecord(h), { wins: 2, losses: 1, draws: 1 });
});
