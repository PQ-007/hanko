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
import '../decks/word_actions.dart';
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
    final forecast = ref.watch(forecastProvider).value;
    final srsToday = ref.watch(srsTodayProvider).value;
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
                      if (forecast != null) ...[
                        _ForecastCard(forecast: forecast, today: srsToday ?? now),
                        const SizedBox(height: 12),
                      ],
                      if (all.isNotEmpty) ...[
                        _Spotlight(words: all, decks: decks, dayKey: srsToday == null ? null : dayKey(srsToday)),
                        const SizedBox(height: 12),
                      ],
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Tooltip(
            message: T.retentionHint,
            child: ProgressRing(
              pct: s?.retentionPct ?? 0,
              centerText: s?.retentionPct == null ? '—' : '${s!.retentionPct!.round()}%',
              label: '${T.retentionLabel}\n${s?.reviewTotal ?? 0}',
              size: 88,
            ),
          ),
          Tooltip(
            message: T.accuracyHint,
            child: ProgressRing(
              pct: s?.accuracyPct ?? 0,
              centerText: s?.accuracyPct == null ? '—' : '${s!.accuracyPct!.round()}%',
              label: '${T.accuracyLabel}\n${s?.total ?? 0}',
              size: 88,
              color: HankoColors.gradeD,
            ),
          ),
          ProgressRing(
            pct: masteredPct,
            label: '${T.masteredRingLabel}\n',
            size: 88,
            color: HankoColors.gradeA,
          ),
        ],
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast, required this.today});
  final Map<DateTime, int> forecast;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    const days = 30;
    final start = dayOnly(today);
    final byKey = {for (final e in forecast.entries) dayKey(e.key): e.value};
    final values = [
      for (var i = 0; i < days; i++)
        byKey[dayKey(DateTime(start.year, start.month, start.day + i))] ?? 0,
    ];
    final total = values.fold<int>(0, (a, b) => a + b);
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);

    return SectionCard(
      title: T.forecastTitle,
      trailing: T.forecastSummary(total, days),
      child: SizedBox(
        height: 140,
        child: BarChart(
          BarChartData(
            maxY: max * 1.15,
            alignment: BarChartAlignment.spaceBetween,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => HankoColors.ink,
                getTooltipItem: (group, _, rod, _) {
                  final d = DateTime(start.year, start.month, start.day + group.x);
                  return BarTooltipItem(
                    '${d.month}/${d.day}\n${T.reviewsN(rod.toY.round())}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 18,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i != 0 && i != 1 && i % 7 != 0) return const SizedBox.shrink();
                    final d = DateTime(start.year, start.month, start.day + i);
                    final label = i == 0 ? T.today : i == 1 ? T.tomorrow : '${d.month}/${d.day}';
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(label, style: const TextStyle(fontSize: 9, color: HankoColors.inkMute)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < days; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: values[i].toDouble(),
                    width: 6,
                    color: i == 0 ? HankoColors.seal : HankoColors.gradeF,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                ]),
            ],
          ),
        ),
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

  static const _steps = [
    HankoColors.gradeF,
    HankoColors.gradeD,
    HankoColors.gradeC,
    HankoColors.gradeB,
    HankoColors.gradeA,
  ];

  @override
  Widget build(BuildContext context) {
    final grid = buildHeatGrid(counts, now);
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
                              style: const TextStyle(fontSize: 8, color: HankoColors.inkMute))
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
                                    -1 => HankoColors.heatmapEmpty,
                                    final s => _steps[s],
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
                getTooltipColor: (_) => HankoColors.ink,
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
                color: HankoColors.gradeD,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: HankoColors.gradeD.withValues(alpha: 0.15),
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
                    Text('${w.totals[i]}', style: const TextStyle(fontSize: 10, color: HankoColors.inkSoft)),
                    const SizedBox(height: 3),
                    Container(
                      width: 20,
                      // Capped at 80% so the label never meets the title.
                      height: w.totals[i] == 0
                          ? 0
                          : (w.totals[i] / max * 100).clamp(6, 80) / 100 * chartH,
                      decoration: const BoxDecoration(
                        color: HankoColors.gradeD,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const Divider(height: 1, color: HankoColors.paperDeep),
                    const SizedBox(height: 4),
                    Text(
                      weekdayMn[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == todayIdx ? FontWeight.w700 : FontWeight.w400,
                        color: i == todayIdx ? HankoColors.ink : HankoColors.inkMute,
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
    return SectionCard(
      title: T.deckBreakdownTitle,
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(flex: 4, child: Text(T.colDeck, style: _head)),
              Expanded(flex: 2, child: Text(T.colWords, style: _head, textAlign: TextAlign.right)),
              Expanded(flex: 2, child: Text(T.colDue, style: _head, textAlign: TextAlign.right)),
              Expanded(flex: 3, child: Text(T.colMastered, style: _head, textAlign: TextAlign.right)),
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
                                color: HankoColors.gradeB,
                                backgroundColor: HankoColors.sealTint,
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

  static const _head = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HankoColors.inkMute);
}

class _Spotlight extends ConsumerStatefulWidget {
  const _Spotlight({required this.words, required this.decks, required this.dayKey});
  final List<Word> words;
  final List<Deck> decks;
  final String? dayKey;

  @override
  ConsumerState<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends ConsumerState<_Spotlight> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final w = widget.words[spotlightIndex(widget.dayKey, _step, widget.words.length)];
    final deckName = widget.decks.where((d) => d.id == w.deckId).firstOrNull?.name;
    final g = gradeOfWord(w);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: HankoColors.seal),
                const SizedBox(width: 6),
                const Text(T.spotlightTitle, style: TextStyle(fontWeight: FontWeight.w600)),
                if (deckName != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(deckName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: HankoColors.inkMute)),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.shuffle, size: 16),
                  label: const Text(T.spotlightAnother),
                  onPressed: () => setState(() => _step += 1),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.term, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                      if (w.reading != null && w.reading != w.term)
                        Text(w.reading!, style: const TextStyle(color: HankoColors.inkSoft)),
                      const SizedBox(height: 6),
                      Text(
                        w.meaningMn?.isNotEmpty == true
                            ? w.meaningMn!
                            : (w.meaning?.isNotEmpty == true ? w.meaning! : T.spotlightNoMeaning),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (w.meaningMn?.isNotEmpty == true && w.meaning?.isNotEmpty == true)
                        Text(w.meaning!, style: const TextStyle(fontSize: 12, color: HankoColors.inkSoft)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(g == Grade.newWord ? 'N' : g.label,
                        style: TextStyle(
                            fontSize: 44, fontWeight: FontWeight.w800, color: gradeColor(g).withValues(alpha: 0.35))),
                    IconButton(
                      icon: const Icon(Icons.volume_up_outlined, color: HankoColors.seal),
                      onPressed: () => playWord(context, ref, w),
                    ),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go(Routes.deck(w.deckId)),
                child: const Text('${T.spotlightOpenDeck} →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
