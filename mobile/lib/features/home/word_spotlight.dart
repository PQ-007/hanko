import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../decks/word_actions.dart';
import '../stats/grade_bars.dart';
import '../stats/stats_math.dart';

/// "Таны үгсээс": one of your own words, shown in full (web WordSpotlight.tsx).
/// Seeded from the scheduler's day, so it's the same word all day and the
/// same word the web dashboard shows; "another" steps forward from there.
class WordSpotlight extends ConsumerStatefulWidget {
  const WordSpotlight({super.key, required this.words, required this.decks, required this.dayKey});
  final List<Word> words;
  final List<Deck> decks;
  final String? dayKey;

  @override
  ConsumerState<WordSpotlight> createState() => _WordSpotlightState();
}

class _WordSpotlightState extends ConsumerState<WordSpotlight> {
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
                        style: TextStyle(fontSize: 11, color: context.hk.inkMute)),
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
                        Text(w.reading!, style: TextStyle(color: context.hk.inkSoft)),
                      const SizedBox(height: 6),
                      Text(
                        w.meaningMn?.isNotEmpty == true
                            ? w.meaningMn!
                            : (w.meaning?.isNotEmpty == true ? w.meaning! : T.spotlightNoMeaning),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (w.meaningMn?.isNotEmpty == true && w.meaning?.isNotEmpty == true)
                        Text(w.meaning!, style: TextStyle(fontSize: 12, color: context.hk.inkSoft)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(g == Grade.newWord ? 'N' : g.label,
                        style: TextStyle(
                            fontSize: 44, fontWeight: FontWeight.w800, color: gradeColor(context.hk, g).withValues(alpha: 0.35))),
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
