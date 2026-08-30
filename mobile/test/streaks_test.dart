import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/stats/streaks.dart';

void main() {
  _freezeTests();

  DateTime d(int day) => DateTime(2026, 8, day);

  group('currentStreak', () {
    test('counts back from today', () {
      expect(currentStreak([d(14), d(15), d(16)], d(16)), 3);
    });

    test('survives today being empty — the day is not over yet', () {
      // Reviewed yesterday but not yet today: the streak is still alive.
      expect(currentStreak([d(14), d(15)], d(16)), 2);
    });

    test('breaks when yesterday is also missing', () {
      expect(currentStreak([d(13), d(14)], d(16)), 0);
    });

    test('a gap stops the count even if older days are contiguous', () {
      expect(currentStreak([d(10), d(11), d(12), d(15), d(16)], d(16)), 2);
    });

    test('no activity at all is zero, not a crash', () {
      expect(currentStreak(const [], d(16)), 0);
    });
  });

  group('longestStreak', () {
    test('finds the longest run anywhere in the history', () {
      expect(longestStreak([d(1), d(2), d(3), d(4), d(10), d(11)]), 4);
    });

    test('is 1 when no two days are adjacent', () {
      expect(longestStreak([d(1), d(5), d(9)]), 1);
    });

    test('is 0 for an empty history', () {
      expect(longestStreak(const []), 0);
    });

    test('duplicate days do not inflate a run', () {
      expect(longestStreak([d(1), d(1), d(2)]), 2);
    });

    test('spans a month boundary', () {
      expect(
        longestStreak([DateTime(2026, 7, 30), DateTime(2026, 7, 31), DateTime(2026, 8, 1)]),
        3,
      );
    });
  });
}

void _freezeTests() {
  DateTime d(int day) => DateTime(2026, 8, day);

  group('currentStreak with freezes', () {
    test('freezesAvailable: 0 behaves exactly like before', () {
      // 14 and 15 are both genuinely active — a plain 2-day streak, no gap
      // involved at all.
      expect(currentStreak([d(14), d(15)], d(16), freezesAvailable: 0), 2);
    });

    test('bridges one gap day between an active day and today', () {
      // Active on 14, missing 15, today (16) has nothing yet.
      // 16 -> skip to 15 (today not active) -> 15 bridged (1) -> 14 active (2)
      // -> 13 missing, no freeze left -> stop.
      expect(currentStreak([d(14)], d(16), freezesAvailable: 1), 2);
    });

    test('bridges a gap strictly between two active runs', () {
      // Active 12,13,14, missing 15, active 16 (today): one freeze stitches
      // the whole run into a single streak of 5.
      expect(
        currentStreak([d(12), d(13), d(14), d(16)], d(16), freezesAvailable: 1),
        5,
      );
    });

    test('a dangling bridge that never reconnects does not count', () {
      // Active 12,13,16; missing 14 and 15. 16 active(1), 15 bridged but out
      // of freezes before reaching 14 — the bridge to 15 never reconnects to
      // real activity, so it's stripped back out. Streak is 1 (today alone),
      // not 2: the freeze was spent for nothing, same as if it were never
      // used.
      expect(
        currentStreak([d(12), d(13), d(16)], d(16), freezesAvailable: 1),
        1,
      );
    });

    test('freezes are a shared budget across the whole walk-back, not per-gap',
        () {
      // Active 10,12,14,16 with two single-day gaps (11, 13, 15) and two
      // freezes: 16(1) 15-bridge(2) 14(3) 13-bridge(4) 12(5) 11-no-freeze-left.
      expect(
        currentStreak([d(10), d(12), d(14), d(16)], d(16), freezesAvailable: 2),
        5,
      );
    });

    test('a freeze never applies to today — today not being active yet is not a miss', () {
      // Active yesterday (15), today (16) has nothing yet. This is already 1
      // under the "stays alive until today ends" rule; a freeze must not be
      // spent trying to bridge "today" itself.
      expect(currentStreak([d(15)], d(16), freezesAvailable: 3), 1);
    });

    test('freezes cannot manufacture a streak out of no activity at all', () {
      // Zero reviews, ever. Every one of the 5 available freezes gets spent
      // walking backward, but none of them ever reconnects to a real active
      // day, so all 5 are stripped back out and the streak is 0 — not a
      // fabricated 5-day streak on an account that has never once reviewed.
      expect(currentStreak(const [], d(16), freezesAvailable: 5), 0);
    });
  });
}
