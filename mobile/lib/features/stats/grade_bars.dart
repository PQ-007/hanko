import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';

Color gradeColor(Grade g) => switch (g) {
      Grade.newWord => HankoColors.gradeNew,
      Grade.f => HankoColors.gradeF,
      Grade.d => HankoColors.gradeD,
      Grade.c => HankoColors.gradeC,
      Grade.b => HankoColors.gradeB,
      Grade.a => HankoColors.gradeA,
    };

/// Words per mastery grade (web GradeChart.tsx). With [onSelect], each bar is
/// a filter: tap to narrow, tap again to clear. Counts always reflect [words]
/// as passed in, never a filtered list, so the chart doesn't shrink under
/// itself.
class GradeBars extends StatelessWidget {
  const GradeBars({
    super.key,
    required this.words,
    this.title = T.gradeTitle,
    this.selected,
    this.onSelect,
  });

  final List<Word> words;
  final String title;
  final Grade? selected;
  final ValueChanged<Grade?>? onSelect;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final g in Grade.values) g: 0};
    for (final w in words) {
      final g = gradeOfWord(w);
      counts[g] = counts[g]! + 1;
    }
    final max = counts.values.fold<int>(1, (a, b) => b > a ? b : a);
    const chartHeight = 96.0;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: HankoColors.inkSoft)),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final g in Grade.values)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: onSelect == null || counts[g] == 0
                          ? null
                          : () => onSelect!(selected == g ? null : g),
                      child: SizedBox(
                        height: chartHeight + 18,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${counts[g]}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: HankoColors.inkSoft)),
                            const SizedBox(height: 3),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic,
                              width: 22,
                              // Capped at 80%: the count sits above the bar,
                              // so a full-height bar would push it into the
                              // title (the same fix the web charts got).
                              height: counts[g] == 0
                                  ? 0
                                  : (counts[g]! / max * 100).clamp(6, 80) /
                                      100 *
                                      chartHeight,
                              decoration: BoxDecoration(
                                color: gradeColor(g).withValues(
                                    alpha: selected == null || selected == g ? 1 : 0.4),
                                borderRadius:
                                    const BorderRadius.vertical(top: Radius.circular(4)),
                                border: selected == g
                                    ? Border.all(color: HankoColors.ink, width: 2)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1, color: HankoColors.paperDeep),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final g in Grade.values)
                  Expanded(
                    child: Text(
                      g.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected == g ? FontWeight.w700 : FontWeight.w400,
                        color: selected == g ? HankoColors.ink : HankoColors.inkMute,
                      ),
                    ),
                  ),
              ],
            ),
            if (selected != null && onSelect != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onSelect!(null),
                  child: const Text(T.gradeClearFilter),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GradeBadge extends StatelessWidget {
  const GradeBadge(this.grade, {super.key});
  final Grade grade;

  @override
  Widget build(BuildContext context) {
    final dark = grade.index >= Grade.c.index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: gradeColor(grade),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        grade == Grade.newWord ? 'N' : grade.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: dark ? Colors.white : HankoColors.ink,
        ),
      ),
    );
  }
}
