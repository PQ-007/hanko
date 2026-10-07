import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/library.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import 'grade_bars.dart';
import 'stats_math.dart';

/// The full statistics page — a port of the web's StatsDashboard, plus the
/// two things the web never had: retention/accuracy and a review forecast
/// (0024's review_stats / review_forecast).
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(allWordsProvider);
    final activity = ref.watch(activityProvider);
    final decks = ref.watch(decksProvider).value ?? const <Deck>[];
    final stats = ref.watch(reviewStatsProvider).value;
    final hero = ref.watch(heroProvider);

    final body = switch ((words, activity)) {
      (AsyncValue(isLoading: true, hasValue: false), _) ||
      (_, AsyncValue(isLoading: true, hasValue: false)) =>
        const LoadingScene(label: T.loadingStats),
      (AsyncValue(:final error?), _) || (_, AsyncValue(:final error?)) =>
        Center(child: Text('${T.loadFailed}\n$error')),
      _ => null,
    };

    final all = words.value ?? const <Word>[];
    final days = activity.value ?? const <DateTime, int>{};
    final reviewCounts = {for (final e in days.entries) dayKey(e.key): e.value};
    final addedCounts = <String, int>{};
    for (final w in all) {
      final k = dayKey(w.dateAdded);
      addedCounts[k] = (addedCounts[k] ?? 0) + 1;
    }
    final now = DateTime.now();
    final mastered = all.where((w) => gradeOfWord(w).mastered).length;

    return Scaffold(
      appBar: AppBar(title: const Text(T.navStats)),
      body: body ??
          (all.isEmpty && days.isEmpty
              ? HeroEmptyState(hero: hero, title: T.noStatsData)
              : RefreshIndicator(
                  onRefresh: () async => ref.refreshAll(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    children: [
                      _RetentionCard(
                        stats: stats,
                        masteredPct: all.isEmpty ? 0 : (mastered / all.length * 100).round(),
                      ),
                      const SizedBox(height: 12),
                      _Heatmap(counts: reviewCounts, title: T.heatmapTitle, formatCount: T.reviewsN, now: now),
                      const SizedBox(height: 12),
                      _Heatmap(counts: addedCounts, title: T.addedHeatmapTitle, formatCount: T.wordsN, now: now),
                      if (all.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _GrowthCard(series: growthSeries(all, now)),
                        const SizedBox(height: 12),
                        GradeBars(words: all, title: T.overallGradeTitle),
                        const SizedBox(height: 12),
                        _WeekdayCard(counts: reviewCounts, now: now),
                      ],
                      const SizedBox(height: 12),
                      _DeckBreakdown(decks: decks, words: all, now: now),
                    ],
                  ),
                )),
    );
  }
}

class _RetentionCard extends StatelessWidget {
  const _RetentionCard({required this.stats, required this.masteredPct});
  final ReviewStats? stats;
  final int masteredPct;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return SectionCard(
      title: T.retentionTitle,
      trailing: T.lastNDays(30),
      // Each ring gets an equal third, so a long label wraps inside its own
      // column instead of pushing the row past the card edge.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Tooltip(
              message: T.retentionHint,
              child: ProgressRing(
                pct: s?.retentionPct ?? 0,
                centerText: s?.retentionPct == null ? '—' : '${s!.retentionPct!.round()}%',
                label: '${T.retentionLabel}\n${s?.reviewTotal ?? 0}',
                size: 84,
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: T.accuracyHint,
              child: ProgressRing(
                pct: s?.accuracyPct ?? 0,
                centerText: s?.accuracyPct == null ? '—' : '${s!.accuracyPct!.round()}%',
                label: '${T.accuracyLabel}\n${s?.total ?? 0}',
                size: 84,
                color: context.hk.gradeD,
              ),
            ),
          ),
          Expanded(
            child: ProgressRing(
              pct: masteredPct,
              label: T.masteredRingLabel,
              size: 84,
              color: context.hk.gradeA,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({
    required this.counts,
    required this.title,
    required this.formatCount,
    required this.now,
  });

  final Map<String, int> counts;
  final String title;
  final String Function(int) formatCount;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final grid = buildHeatGrid(counts, now);
    final hk = context.hk;
    final steps = [hk.gradeF, hk.gradeD, hk.gradeC, hk.gradeB, hk.gradeA];
    return SectionCard(
      title: title,
      trailing: T.heatmapSummary(formatCount(grid.total), grid.activeDays),
      child: LayoutBuilder(builder: (context, c) {
        const labelW = 20.0;
        const gap = 2.0;
        final cell = ((c.maxWidth - labelW) / grid.columns.length - gap).clamp(6.0, 14.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelW,
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    SizedBox(
                      height: cell + gap,
                      child: d.isOdd
                          ? Text(weekdayMn[d],
                              style: TextStyle(fontSize: 8, color: context.hk.inkMute))
                          : null,
                    ),
                ],
              ),
            ),
            for (final col in grid.columns)
              Padding(
                padding: const EdgeInsets.only(right: gap),
                child: Column(
                  children: [
                    for (final cellData in col)
                      Tooltip(
                        message: '${cellData.day.month}/${cellData.day.day} · ${formatCount(cellData.count)}',
                        child: Container(
                          width: cell,
                          height: cell,
                          margin: const EdgeInsets.only(bottom: gap),
                          decoration: BoxDecoration(
                            color: cellData.future
                                ? Colors.transparent
                                : switch (heatStep(cellData.count, grid.max)) {
                                    -1 => context.hk.heatmapEmpty,
                                    final s => steps[s],
                                  },
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _GrowthCard extends StatelessWidget {
  const _GrowthCard({required this.series});
  final List<({DateTime day, int total})> series;

  @override
  Widget build(BuildContext context) {
    final totals = series.map((p) => p.total);
    final min = totals.reduce((a, b) => a < b ? a : b);
    final max = totals.reduce((a, b) => a > b ? a : b);
    return SectionCard(
      title: T.growthTitle(series.length),
      trailing: '${series.last.total} ${T.wordsUnit}',
      child: SizedBox(
        height: 130,
        child: LineChart(
          LineChartData(
            minY: min.toDouble(),
            maxY: (max == min ? max + 1 : max).toDouble(),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF1F2933),
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${series[s.x.toInt()].day.month}/${series[s.x.toInt()].day.day}\n'
                      '${s.y.round()} ${T.wordsUnit}',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < series.length; i++)
                    FlSpot(i.toDouble(), series[i].total.toDouble()),
                ],
                color: context.hk.gradeD,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: context.hk.gradeD.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekdayCard extends StatelessWidget {
  const _WeekdayCard({required this.counts, required this.now});
  final Map<String, int> counts;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final w = weekdayTotals(counts, now);
    final grand = w.totals.fold<int>(0, (a, b) => a + b);
    final max = w.totals.fold<int>(1, (a, b) => b > a ? b : a);
    final todayIdx = now.weekday % 7;
    const chartH = 90.0;
    return SectionCard(
      title: T.weekdayTitle,
      trailing: T.weekdaySummary(grand),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Tooltip(
                message:
                    '${T.reviewsN(w.totals[i])} · ${T.perWeekAvg(w.seen[i] == 0 ? 0 : (w.totals[i] / w.seen[i] * 10).round() / 10)}',
                child: Column(
                  children: [
                    Text('${w.totals[i]}', style: TextStyle(fontSize: 10, color: context.hk.inkSoft)),
                    const SizedBox(height: 3),
                    Container(
                      width: 20,
                      // Capped at 80% so the label never meets the title.
                      height: w.totals[i] == 0
                          ? 0
                          : (w.totals[i] / max * 100).clamp(6, 80) / 100 * chartH,
                      decoration: BoxDecoration(
                        color: context.hk.gradeD,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    Divider(height: 1, color: context.hk.paperDeep),
                    const SizedBox(height: 4),
                    Text(
                      weekdayMn[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == todayIdx ? FontWeight.w700 : FontWeight.w400,
                        color: i == todayIdx ? context.hk.ink : context.hk.inkMute,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckBreakdown extends StatelessWidget {
  const _DeckBreakdown({required this.decks, required this.words, required this.now});
  final List<Deck> decks;
  final List<Word> words;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final byDeck = <String, List<Word>>{};
    for (final w in words) {
      (byDeck[w.deckId] ??= []).add(w);
    }
    final head = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.hk.inkMute);
    return SectionCard(
      title: T.deckBreakdownTitle,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(flex: 4, child: Text(T.colDeck, style: head)),
              Expanded(flex: 2, child: Text(T.colWords, style: head, textAlign: TextAlign.right)),
              Expanded(flex: 2, child: Text(T.colDue, style: head, textAlign: TextAlign.right)),
              Expanded(flex: 3, child: Text(T.colMastered, style: head, textAlign: TextAlign.right)),
            ],
          ),
          const Divider(),
          for (final d in decks)
            () {
              final ws = byDeck[d.id] ?? const <Word>[];
              final due = ws.where((w) => w.dueAt != null && !w.dueAt!.isAfter(now)).length;
              final m = ws.isEmpty ? 0.0 : ws.where((w) => gradeOfWord(w).mastered).length / ws.length;
              return InkWell(
                onTap: () => context.go(Routes.deck(d.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(d.name, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: Text('${ws.length}', textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text('$due', textAlign: TextAlign.right)),
                      Expanded(
                        flex: 3,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 40,
                              child: LinearProgressIndicator(
                                value: m,
                                minHeight: 5,
                                color: context.hk.gradeB,
                                backgroundColor: context.hk.sealTint,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('${(m * 100).round()}%', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }

}
