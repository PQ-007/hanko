import { test } from "node:test";
import assert from "node:assert/strict";
import { currentStreak, localDateKey, longestStreak, startOfDay } from "./dates.ts";

// The streak walk is the one number on the dashboard a user will notice being
// wrong, and it is computed from two things that can disagree: the day keys
// review_activity() returns (bucketed at the SRS cutoff, 4am) and whatever the
// walk thinks "today" is. These pin that seam.

const days = (...keys: string[]) => new Set(keys);

test("counts a run ending on the given day", () => {
  assert.equal(
    currentStreak(days("2026-08-28", "2026-08-29", "2026-08-30"), 0, "2026-08-30"),
    3
  );
});

test("a quiet today does not break a streak that ran to yesterday", () => {
  // The day is not over yet, so it is not a miss.
  assert.equal(currentStreak(days("2026-08-28", "2026-08-29"), 0, "2026-08-30"), 2);
});

test("two quiet days do break it", () => {
  assert.equal(currentStreak(days("2026-08-27", "2026-08-28"), 0, "2026-08-30"), 0);
});

test("the SRS day is what decides, not the device's date", () => {
  // A review at 01:00 lands on the previous SRS day (cutoff 4am). A client
  // walking from its own date would start on 08-30, find nothing, step back to
  // 08-29 and get the right answer by luck. Given 08-29 directly it is right
  // by construction — and, unlike the lucky path, it stays right when the
  // device's clock or timezone disagrees with the profile.
  const active = days("2026-08-28", "2026-08-29");
  assert.equal(currentStreak(active, 0, "2026-08-29"), 2, "scheduler's today");
  assert.equal(currentStreak(active, 0, "2026-08-30"), 2, "device's today");
  // Where they genuinely diverge: a gap on the scheduler's yesterday.
  const gapped = days("2026-08-27", "2026-08-29");
  assert.equal(currentStreak(gapped, 0, "2026-08-29"), 1);
  assert.equal(currentStreak(gapped, 0, "2026-08-30"), 1);
});

test("a freeze bridges a single missed day", () => {
  // 27th, [28th bridged], 29th, 30th — the bridge reconnects to a real active
  // day, so everything on the far side of it counts too.
  assert.equal(
    currentStreak(days("2026-08-27", "2026-08-29", "2026-08-30"), 1, "2026-08-30"),
    4
  );
  // Without the freeze the run stops at the gap.
  assert.equal(
    currentStreak(days("2026-08-27", "2026-08-29", "2026-08-30"), 0, "2026-08-30"),
    2
  );
});

test("a freeze that never reconnects is stripped back out", () => {
  // The bug this guards: a brand-new account with zero reviews and the default
  // allotment would otherwise report a streak it never earned.
  assert.equal(currentStreak(days(), 2, "2026-08-30"), 0);
  assert.equal(currentStreak(days("2026-08-30"), 2, "2026-08-30"), 1);
});

test("freezes are spent, not unlimited", () => {
  // Two adjacent gaps, one freeze: the bridge runs out and nothing before it
  // can count.
  assert.equal(
    currentStreak(days("2026-08-26", "2026-08-29", "2026-08-30"), 1, "2026-08-30"),
    2
  );
});

test("falling back to the device date still works", () => {
  const today = localDateKey(startOfDay(new Date()));
  assert.equal(currentStreak(days(today), 0), 1, "no `today` argument given");
});

test("longestStreak finds the best run anywhere in history", () => {
  assert.equal(
    longestStreak(days("2026-01-01", "2026-01-02", "2026-01-03", "2026-06-01")),
    3
  );
  assert.equal(longestStreak(days()), 0);
});
