import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repository.dart';
import 'streaks.dart';

final _activityProvider = FutureProvider<Map<DateTime, int>>(
  (ref) => ref.watch(repositoryProvider).reviewActivity(),
);

/// Streaks and recent activity, matching the web dashboard.
///
/// Everything here is derived from `review_activity()`, so the numbers agree
/// with the web app by construction rather than by two implementations
/// happening to round the same way.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(_activityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Статистик')),
      body: activity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Уншиж чадсангүй:\n$e'),
        ),
        data: (days) => _StatsBody(days: days),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.days});

  final Map<DateTime, int> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final streak = currentStreak(days.keys, now);
    final best = longestStreak(days.keys);
    final total = days.values.fold<int>(0, (a, b) => a + b);

    // Last 7 SRS days, oldest first.
    final week = <MapEntry<DateTime, int>>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = days.keys.firstWhere(
        (k) => k.year == d.year && k.month == d.month && k.day == d.day,
        orElse: () => d,
      );
      week.add(MapEntry(d, days[key] ?? 0));
    }
    final weekTotal = week.fold<int>(0, (a, e) => a + e.value);
    final weekMax = week.fold<int>(1, (a, e) => e.value > a ? e.value : a);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('🔥', style: theme.textTheme.headlineSmall),
                Text('$streak', style: theme.textTheme.displaySmall),
                Text('дараалсан өдөр', style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'Хамгийн урт: $best өдөр',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Tile(label: 'Энэ 7 хоног', value: '$weekTotal')),
            const SizedBox(width: 8),
            Expanded(child: _Tile(label: 'Нийт давталт', value: '$total')),
            const SizedBox(width: 8),
            Expanded(child: _Tile(label: 'Идэвхтэй өдөр', value: '${days.length}')),
          ],
        ),
        const SizedBox(height: 20),
        Text('Сүүлийн 7 хоног', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final e in week)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${e.value}',
                            style: const TextStyle(fontSize: 10)),
                        const SizedBox(height: 2),
                        Container(
                          height: (e.value / weekMax * 70).clamp(2, 70).toDouble(),
                          decoration: BoxDecoration(
                            color: e.value == 0
                                ? Colors.grey.shade300
                                : theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _weekday(e.key.weekday),
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _weekday(int w) =>
      const ['Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя', 'Ня'][w - 1];
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
