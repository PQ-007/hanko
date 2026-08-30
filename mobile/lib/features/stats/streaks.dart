/// Streak arithmetic over the set of days that had reviews.
///
/// The days come from `review_activity()`, already bucketed by the user's SRS
/// day cutoff — so "a day" means the same thing here, in the review queue, and
/// on the web dashboard. Computing the boundary client-side is what would let
/// those three drift apart.
library;

int _dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

/// Longest run of consecutive days present in [days].
int longestStreak(Iterable<DateTime> days) {
  final nums = days.map(_dayNumber).toSet().toList()..sort();
  if (nums.isEmpty) return 0;
  var best = 1;
  var run = 1;
  for (var i = 1; i < nums.length; i++) {
    run = nums[i] - nums[i - 1] == 1 ? run + 1 : 1;
    if (run > best) best = run;
  }
  return best;
}

/// Current run ending today — or yesterday, since a streak stays alive until
/// the day is actually over. [today] is the current SRS day.
///
/// [freezesAvailable] is `profiles.streak_freezes` (0014_gamification.sql): a
/// pure read, not a spend — a missed day within budget is bridged and still
/// counts toward the streak, exactly like a real active day, but nothing here
/// writes the freeze count back down. Deliberately simple for a first cut: a
/// real spend/earn economy is future work, not this pass. Two consecutive
/// missed days can never both be bridged by one freeze, same as one shield
/// can't cover two hits.
int currentStreak(Iterable<DateTime> days, DateTime today, {int freezesAvailable = 0}) {
  final nums = days.map(_dayNumber).toSet();
  var cursor = _dayNumber(today);
  // A freeze only ever bridges a *past, completed* day. Today not having
  // activity yet isn't a miss — the day isn't over — so this check stays
  // unconditional: skip to yesterday first, then let freezes apply only to
  // the backward walk over days that have actually finished.
  if (!nums.contains(cursor)) cursor -= 1;
  var streak = 0;
  var freezesLeft = freezesAvailable;
  // Days counted via a freeze since the last confirmed active day. A freeze
  // only means anything if it reconnects two real active days (or an active
  // day and today, still in progress) — bridging a gap that never resolves
  // back to real activity isn't a streak, it's freezes spent into a void.
  // Without stripping this back out, a brand-new account with zero reviews
  // ever but the default freeze allotment would show a fabricated streak.
  var unconfirmed = 0;
  while (true) {
    if (nums.contains(cursor)) {
      streak += 1;
      unconfirmed = 0;
    } else if (freezesLeft > 0) {
      freezesLeft -= 1;
      streak += 1;
      unconfirmed += 1;
    } else {
      break;
    }
    cursor -= 1;
  }
  return streak - unconfirmed;
}
