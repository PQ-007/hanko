import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/stats/stats_math.dart';
import 'package:mobile/models/library.dart';

Word wordAdded(DateTime d) => Word(id: '$d', deckId: 'd', term: 't', dateAdded: d);

void main() {
  test('seedFrom matches the web WordSpotlight seed bit for bit', () {
    // Values computed by running seedFrom from WordSpotlight.tsx in Node.
    expect(seedFrom(''), 2166136261);
    expect(seedFrom('2026-10-04'), 1618814878);
    expect(seedFrom('2026-10-05'), 1635592497);
    expect(seedFrom('2026-01-01'), 2049302883);
    expect(seedFrom('猫'), 780935338);
  });

  test('consecutive days land on different spotlight words', () {
    expect(spotlightIndex('2026-10-04', 0, 50), isNot(spotlightIndex('2026-10-05', 0, 50)));
    expect(spotlightIndex('2026-10-04', 1, 50), (spotlightIndex('2026-10-04', 0, 50) + 1) % 50);
  });

  test('dayKey zero-pads like localDateKey', () {
    expect(dayKey(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('heatStep thresholds match heatmapColor in chartColors.ts', () {
    expect(heatStep(0, 10), -1);
    expect(heatStep(1, 1), 2);
    expect(heatStep(2, 10), 0);
    expect(heatStep(5, 10), 1);
    expect(heatStep(7, 10), 2);
    expect(heatStep(9, 10), 3);
    expect(heatStep(10, 10), 4);
  });

  test('heat grid is 26 Sunday-first weeks ending on this Saturday', () {
    final now = DateTime(2026, 10, 7); // a Wednesday
    final grid = buildHeatGrid({'2026-10-05': 3, '2026-10-06': 1}, now);
    expect(grid.columns.length, 26);
    expect(grid.columns.first.first.day.weekday, DateTime.sunday);
    expect(grid.columns.last.last.day, DateTime(2026, 10, 10)); // Saturday
    expect(grid.total, 4);
    expect(grid.activeDays, 2);
    expect(grid.columns.last.last.future, isTrue);
  });

  test('growth series counts words from before the window', () {
    final now = DateTime(2026, 10, 7);
    final series = growthSeries([
      wordAdded(DateTime(2025, 1, 1)),
      wordAdded(DateTime(2026, 10, 6, 15)),
      wordAdded(DateTime(2026, 10, 7, 9)),
    ], now, days: 3);
    expect(series.map((p) => p.total), [1, 2, 3]);
  });

  test('weekday totals count each weekday 26 times', () {
    final w = weekdayTotals({'2026-10-04': 5}, DateTime(2026, 10, 7));
    expect(w.seen, List.filled(7, 26));
    expect(w.totals[0], 5); // 2026-10-04 is a Sunday
  });
}
