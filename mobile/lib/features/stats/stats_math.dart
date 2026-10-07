// Pure helpers behind the Stats tab, each a port of the matching web chart so
// the two dashboards draw the same picture from the same data.

import '../../models/library.dart';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `YYYY-MM-DD`, the key `review_activity()` and the web's localDateKey use.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// FNV-1a over UTF-16 code units — `seedFrom` in WordSpotlight.tsx, bit for
/// bit, so the word of the day is the same word on both clients.
int seedFrom(String key) {
  var h = 2166136261;
  for (final c in key.codeUnits) {
    h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// Index of today's spotlight word in a list of [length] (ordered by id).
int spotlightIndex(String? key, int step, int length) =>
    (seedFrom(key ?? '') + step) % length;

/// Heatmap step 0–4, or -1 for an empty day (`heatmapColor` in chartColors.ts).
int heatStep(int count, int max) {
  if (count <= 0) return -1;
  if (max <= 1) return 2;
  final r = count / max;
  if (r <= 0.25) return 0;
  if (r <= 0.5) return 1;
  if (r <= 0.75) return 2;
  if (r < 1) return 3;
  return 4;
}

class HeatCell {
  const HeatCell(this.day, this.count, this.future);
  final DateTime day;
  final int count;
  final bool future;
}

class HeatGrid {
  const HeatGrid(this.columns, this.max, this.total, this.activeDays);
  final List<List<HeatCell>> columns;
  final int max;
  final int total;
  final int activeDays;
}

/// [weeks] Sunday-first columns ending on this week's Saturday
/// (ActivityHeatmap.tsx).
HeatGrid buildHeatGrid(Map<String, int> counts, DateTime now, {int weeks = 26}) {
  final today = dayOnly(now);
  final dow = today.weekday % 7; // Sunday = 0, as JS getDay()
  final end = today.add(Duration(days: 6 - dow));
  final start = end.subtract(Duration(days: weeks * 7 - 1));
  final cols = <List<HeatCell>>[];
  var max = 0, total = 0, active = 0;
  for (var w = 0; w < weeks; w++) {
    final col = <HeatCell>[];
    for (var d = 0; d < 7; d++) {
      final day = DateTime(start.year, start.month, start.day + w * 7 + d);
      final c = counts[dayKey(day)] ?? 0;
      if (c > max) max = c;
      total += c;
      if (c > 0) active += 1;
      col.add(HeatCell(day, c, day.isAfter(today)));
    }
    cols.add(col);
  }
  return HeatGrid(cols, max, total, active);
}

/// Cumulative word count for each of the last [days] days (GrowthChart.tsx).
List<({DateTime day, int total})> growthSeries(List<Word> words, DateTime now, {int days = 90}) {
  final today = dayOnly(now);
  final start = DateTime(today.year, today.month, today.day - (days - 1));
  final perDay = <String, int>{};
  var before = 0;
  for (final w in words) {
    final added = dayOnly(w.dateAdded);
    if (added.isBefore(start)) {
      before += 1;
      continue;
    }
    final k = dayKey(added);
    perDay[k] = (perDay[k] ?? 0) + 1;
  }
  var running = before;
  return [
    for (var i = 0; i < days; i++)
      () {
        final day = DateTime(start.year, start.month, start.day + i);
        running += perDay[dayKey(day)] ?? 0;
        return (day: day, total: running);
      }(),
  ];
}

/// Reviews per weekday (Sunday = 0) over the last [weeks] weeks, plus how many
/// times each weekday occurred, for the per-week average
/// (WeekdayReviewsChart.tsx).
({List<int> totals, List<int> seen}) weekdayTotals(
  Map<String, int> counts,
  DateTime now, {
  int weeks = 26,
}) {
  final today = dayOnly(now);
  final totals = List.filled(7, 0);
  final seen = List.filled(7, 0);
  for (var i = 0; i < weeks * 7; i++) {
    final day = DateTime(today.year, today.month, today.day - i);
    final w = day.weekday % 7;
    seen[w] += 1;
    totals[w] += counts[dayKey(day)] ?? 0;
  }
  return (totals: totals, seen: seen);
}
