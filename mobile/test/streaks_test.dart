import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/stats/streaks.dart';

void main() {
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
