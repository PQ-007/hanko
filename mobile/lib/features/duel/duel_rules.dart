import 'dart:math';

import '../battle/rules.dart' show Rand;

/// Duel rules — a port of web/src/app/decks/review/duel/_lib/duel.ts and
/// bot.ts (PVP.md phases 1–2), pinned to them by the same golden fixture the
/// SQL `duel_damage()` is pinned by (duel.fixture.json, 484 cases). Three
/// implementations of one damage rule; the fixture is what keeps them one.
///
/// Not built on Monster Hunt's rules.dart, for the reasons in duel.ts: a duel
/// has two answer streams, no respawn, no randomness in damage (both clients
/// and the server must compute the same number), and ends on HP or rounds.

const duelMaxHp = 100;
const duelRoundCount = 12;

const _firstRoundMs = 10000;
const _finalRoundMs = 6000;
const _tightenPerRoundMs = 500;

/// 10 s in round 1, tightening by 0.5 s a round to a 6 s floor.
int roundDurationMs(int roundNo) => max(_finalRoundMs, _firstRoundMs - (max(1, roundNo) - 1) * _tightenPerRoundMs);

/// Used when the player has too few reviews for a personal median.
const fallbackBaselineMs = 4500;

const _elapsedFloorMs = 350;
const _minSpeedRatio = 0.6;
const _maxSpeedRatio = 1.6;
const _baseDamage = 8;

const duelStreakTiers = [3, 6];
const _streakMultipliers = [1.0, 1.2, 1.4];

int duelStreakTier(int streak) {
  if (streak >= duelStreakTiers[1]) return 2;
  if (streak >= duelStreakTiers[0]) return 1;
  return 0;
}

/// How fast an answer was *for this player*, against their own median.
double speedRatio(int elapsedMs, int? baselineMs) {
  final baseline = baselineMs != null && baselineMs > 0 ? baselineMs : fallbackBaselineMs;
  final elapsed = max(_elapsedFloorMs, elapsedMs);
  return (baseline / elapsed).clamp(_minSpeedRatio, _maxSpeedRatio);
}

class DuelAnswer {
  const DuelAnswer({required this.correct, required this.elapsedMs});
  final bool correct;
  final int elapsedMs;
}

/// JavaScript's Math.round (halves round up), so a .5 lands the same as on
/// the web and in Postgres.
int _jsRound(double v) => (v + 0.5).floor();

/// Damage one answer deals; null is a round the player let expire. Wrong and
/// timed-out answers deal nothing and carry no self-penalty.
int roundDamage(DuelAnswer? answer, int? baselineMs, int streakBefore) {
  if (answer == null || !answer.correct) return 0;
  final multiplier = _streakMultipliers[duelStreakTier(streakBefore)];
  return _jsRound(_baseDamage * speedRatio(answer.elapsedMs, baselineMs) * multiplier);
}

class ResolvedRound {
  const ResolvedRound({
    required this.roundNo,
    required this.you,
    required this.them,
    required this.yourDamage,
    required this.theirDamage,
  });
  final int roundNo;
  final DuelAnswer? you;
  final DuelAnswer? them;

  /// Damage you dealt to them, and they to you.
  final int yourDamage;
  final int theirDamage;
}

class DuelState {
  const DuelState({
    this.yourHp = duelMaxHp,
    this.theirHp = duelMaxHp,
    this.yourStreak = 0,
    this.theirStreak = 0,
    this.roundsPlayed = 0,
    this.lastYourDamage = 0,
    this.lastTheirDamage = 0,
  });
  final int yourHp, theirHp, yourStreak, theirStreak, roundsPlayed, lastYourDamage, lastTheirDamage;
  bool get yourDefeated => yourHp <= 0;
  bool get theirDefeated => theirHp <= 0;
}

/// Decides one round's damage. Call exactly once per round, against the
/// state before it.
ResolvedRound resolveRound(
  int roundNo,
  DuelAnswer? you,
  DuelAnswer? them,
  int? yourBaselineMs,
  int? theirBaselineMs,
  DuelState before,
) =>
    ResolvedRound(
      roundNo: roundNo,
      you: you,
      them: them,
      yourDamage: roundDamage(you, yourBaselineMs, before.yourStreak),
      theirDamage: roundDamage(them, theirBaselineMs, before.theirStreak),
    );

/// Pure fold over decided rounds. Both sides' damage lands together, which
/// is what makes a simultaneous knockout — a draw — reachable.
DuelState deriveDuelState(List<ResolvedRound> rounds) {
  var yourHp = duelMaxHp, theirHp = duelMaxHp, yourStreak = 0, theirStreak = 0;
  var lastYour = 0, lastTheir = 0;
  for (final r in rounds) {
    theirHp = max(0, theirHp - r.yourDamage);
    yourHp = max(0, yourHp - r.theirDamage);
    yourStreak = (r.you?.correct ?? false) ? yourStreak + 1 : 0;
    theirStreak = (r.them?.correct ?? false) ? theirStreak + 1 : 0;
    lastYour = r.yourDamage;
    lastTheir = r.theirDamage;
  }
  return DuelState(
    yourHp: yourHp,
    theirHp: theirHp,
    yourStreak: yourStreak,
    theirStreak: theirStreak,
    roundsPlayed: rounds.length,
    lastYourDamage: lastYour,
    lastTheirDamage: lastTheir,
  );
}

enum DuelOutcome { ongoing, won, lost, draw }

DuelOutcome duelOutcome(DuelState s, {int roundCount = duelRoundCount}) {
  if (s.yourDefeated && s.theirDefeated) return DuelOutcome.draw;
  if (s.yourDefeated) return DuelOutcome.lost;
  if (s.theirDefeated) return DuelOutcome.won;
  if (s.roundsPlayed >= roundCount) {
    if (s.yourHp > s.theirHp) return DuelOutcome.won;
    if (s.yourHp < s.theirHp) return DuelOutcome.lost;
    return DuelOutcome.draw;
  }
  return DuelOutcome.ongoing;
}

// ---- Bot (bot.ts) ------------------------------------------------------------

enum BotDifficulty { rookie, rival, master }

class BotProfile {
  const BotProfile({required this.accuracy, required this.meanReactionMs, required this.reactionJitterMs});
  final double accuracy;
  final int meanReactionMs;
  final int reactionJitterMs;
}

/// First-pass numbers, the web's exactly (PVP.md phase 5 tunes them).
const botProfiles = {
  BotDifficulty.rookie: BotProfile(accuracy: 0.55, meanReactionMs: 7200, reactionJitterMs: 2800),
  BotDifficulty.rival: BotProfile(accuracy: 0.75, meanReactionMs: 5200, reactionJitterMs: 2200),
  BotDifficulty.master: BotProfile(accuracy: 0.9, meanReactionMs: 3400, reactionJitterMs: 1400),
};

/// One round's bot answer, or null when its reaction runs past the timer.
/// Draw order is part of the contract: reaction first, correctness second.
DuelAnswer? botAnswer(BotProfile p, Rand rng, int roundDurationMs) {
  final jitter = (rng() * 2 - 1) * p.reactionJitterMs;
  final elapsedMs = max(200, _jsRound(p.meanReactionMs + jitter));
  final correct = rng() < p.accuracy;
  if (elapsedMs >= roundDurationMs) return null;
  return DuelAnswer(correct: correct, elapsedMs: elapsedMs);
}

/// A bot is measured against itself too: its own mean reaction.
int botBaselineMs(BotProfile p) => p.meanReactionMs;
