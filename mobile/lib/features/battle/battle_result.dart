import 'package:flutter/material.dart';

import '../../core/strings.dart';
import 'rules.dart';
import 'sprite_view.dart';

const _paper = Color(0xFFFAF7F0);

/// Past this the corpses stop being a scene and become a spreadsheet; the
/// rest are summarised as "+N" (BattleResult.tsx).
const _maxTrophies = 8;

/// Longest run of consecutive correct answers in the session.
int bestStreakOf(List<BattleEvent> events) {
  var best = 0, run = 0;
  for (final e in events) {
    if (!e.correct) {
      run = 0;
    } else {
      run += 1;
      if (run > best) best = run;
    }
  }
  return best;
}

/// The end of a hunt: player defeated, or the queue is done. Beating a monster
/// never lands here — the next one spawns in place.
class BattleResultView extends StatelessWidget {
  const BattleResultView({
    super.key,
    required this.outcome,
    required this.reviewedCount,
    required this.defeatedMonsters,
    required this.events,
    required this.monster,
    required this.hero,
    required this.monsterDown,
    required this.onStop,
    this.onRetry,
  });

  final BattleOutcome outcome;
  final int reviewedCount;
  final List<String> defeatedMonsters;
  final List<BattleEvent> events;
  final String monster;
  final String hero;

  /// True only when the run ended on the blow that killed the monster on
  /// screen — then it counts, and lies with the others.
  final bool monsterDown;
  final VoidCallback onStop;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final defeated = outcome == BattleOutcome.defeat;
    final kills = monsterDown ? [...defeatedMonsters, monster] : defeatedMonsters;
    // Killing anything makes the run a win, even if the player fell after.
    final won = kills.isNotEmpty;
    final correct = events.where((e) => e.correct).length;
    final crits = events.where((e) => e.crit).length;
    final trophySize = kills.length == 1
        ? 150.0
        : kills.length <= 3
            ? 104.0
            : 72.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: (defeated ? const Color(0xFFF87171) : const Color(0xFF34D399)).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              T.resultKicker.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
                color: defeated ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            defeated ? T.defeatTitle : (won ? T.victoryTitle : T.clearedTitle),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _paper, fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            defeated ? T.defeatDesc : (won ? T.victoryDesc : T.clearedDesc),
            textAlign: TextAlign.center,
            style: TextStyle(color: _paper.withValues(alpha: 0.55), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          // The scene, not a summary line: everything you killed lies here.
          if (kills.isEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (defeated) SpriteView(slug: hero, state: 'death', size: 110),
                SpriteView(slug: monster, size: defeated ? 110 : 150, flip: true),
              ],
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final slug in kills.take(_maxTrophies))
                  SpriteView(slug: slug, state: 'death', size: trophySize, flip: true),
                if (kills.length > _maxTrophies)
                  Text('+${kills.length - _maxTrophies}',
                      style: TextStyle(
                          color: _paper.withValues(alpha: 0.6), fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            kills.isNotEmpty ? T.monstersDefeated(kills.length) : T.noMonsterDefeated,
            style: TextStyle(color: _paper.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          // reviewedCount spans the whole visit (a retry doesn't un-review
          // words); the others come from `events`, which a retry clears.
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: [
              _Tile(label: T.resultWords, value: '$reviewedCount'),
              _Tile(label: T.resultCrits, value: '$crits'),
              _Tile(label: T.resultCorrect, value: '$correct/${events.length}'),
              _Tile(label: T.resultBestStreak, value: '${bestStreakOf(events)}'),
            ],
          ),
          const SizedBox(height: 22),
          if (defeated && onRetry != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.replay),
                label: const Text(T.retryBattle),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.close),
              label: const Text(T.stopBattle),
              style: OutlinedButton.styleFrom(
                foregroundColor: _paper,
                side: BorderSide(color: _paper.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(color: _paper, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: _paper.withValues(alpha: 0.55), fontSize: 11)),
        ],
      ),
    );
  }
}
