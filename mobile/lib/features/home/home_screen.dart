import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../battle/hero_picker.dart';
import '../battle/sprite_view.dart';
import '../shell/action_sheet.dart';
import '../shell/quick_add_sheet.dart';
import '../stats/streaks.dart';
import 'goal_dialog.dart';

/// Minimal on purpose: what's due, the streak, today's progress, and the way
/// into the main actions. Everything else lives on the Stats tab.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The SRS day boundary is evaluated server-side in this timezone, and
      // phones are the one client that actually changes timezone.
      try {
        final tz = await FlutterTimezone.getLocalTimezone();
        await ref.read(repositoryProvider).syncTimezone(tz.identifier);
      } catch (_) {
        // Non-fatal: the server falls back to UTC.
      }
      // Re-forecast tonight's reminder against current state, so it doesn't
      // quote this morning's backlog after a session.
      try {
        final reminders = await ref.read(remindersProvider.future);
        await reminders.reschedule();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final due = ref.watch(dueSummaryProvider);
    final activity = ref.watch(activityProvider);
    final freezes = ref.watch(freezesProvider).value ?? 0;
    final srsToday = ref.watch(srsTodayProvider).value;
    final words = ref.watch(allWordsProvider).value ?? const [];
    final hero = ref.watch(heroProvider);
    final theme = Theme.of(context);

    final days = activity.value ?? const <DateTime, int>{};
    final now = srsToday ?? DateTime.now();
    final streak = currentStreak(days.keys, now, freezesAvailable: freezes);
    final best = longestStreak(days.keys);
    final today = DateTime.now();
    final addedToday = words
        .where((w) =>
            w.dateAdded.year == today.year &&
            w.dateAdded.month == today.month &&
            w.dateAdded.day == today.day)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('Hanko', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(width: 8),
            Text('Verba non Acta',
                style: TextStyle(
                    fontSize: 12, fontStyle: FontStyle.italic, color: HankoColors.inkMute)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: T.settings,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: (due.isLoading && !due.hasValue) || (activity.isLoading && !activity.hasValue)
          ? const LoadingScene(label: T.loading)
          : RefreshIndicator(
              onRefresh: () async => ref.refreshAll(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  // Streak, with your hero beside it. Tap the hero to change.
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 20, 12),
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(60),
                            onTap: () => showHeroPicker(context),
                            child: SpriteView(slug: hero, size: 104),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$streak',
                                        style: const TextStyle(
                                            fontSize: 52,
                                            height: 1,
                                            fontWeight: FontWeight.w700,
                                            color: HankoColors.ink)),
                                    const SizedBox(width: 6),
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 6),
                                      child: Icon(Icons.local_fire_department,
                                          color: HankoColors.seal),
                                    ),
                                  ],
                                ),
                                const Text(T.streakLabel,
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                Text(T.bestStreak(best),
                                    style: const TextStyle(
                                        fontSize: 12, color: HankoColors.inkMute)),
                                if (freezes > 0)
                                  Text('❄ ${T.streakFreezes(freezes)}',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.lightBlue.shade700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Today's workload.
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: due.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('${T.loadFailed}: $e'),
                        data: (d) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(T.practiceKicker.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w700,
                                    color: HankoColors.seal)),
                            const SizedBox(height: 4),
                            Text(
                              d.dueNow > 0
                                  ? T.practiceDueHeadline(d.dueNow)
                                  : T.practiceNothingDue,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (d.heldBack > 0)
                              Text(T.dueHeldBack(d.heldBack),
                                  style: const TextStyle(
                                      fontSize: 12, color: HankoColors.inkMute)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text(T.practiceAll),
                              onPressed: () => startReviewFlow(context, ref),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Today's progress.
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => showGoalDialog(context, ref, due.value?.newGoal ?? 20),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: ProgressRing(
                                pct: due.value?.goalPct ?? 0,
                                centerText:
                                    '${due.value?.newReviewedToday ?? 0}/${due.value?.newGoal ?? 0}',
                                label: '${T.goalRingLabel} ✎',
                              ),
                            ),
                          ),
                          ProgressRing(
                            pct: 100,
                            centerText: '$addedToday',
                            label: T.addedRingLabel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Shortcut(
                        icon: Icons.add_circle_outline,
                        label: T.actionAddWord,
                        onTap: () => showQuickAddSheet(context, ref),
                      ),
                      const SizedBox(width: 10),
                      _Shortcut(
                        leading: SpriteView(slug: hero, state: 'attack01', size: 40),
                        label: T.battleModeTitle,
                        onTap: () => startReviewFlow(context, ref),
                      ),
                      const SizedBox(width: 10),
                      _Shortcut(
                        icon: Icons.collections_bookmark_outlined,
                        label: T.navLibrary,
                        onTap: () => context.go(Routes.library),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({this.icon, this.leading, required this.label, required this.onTap});
  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Center(
                    child: leading ?? Icon(icon, color: HankoColors.seal, size: 28),
                  ),
                ),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
