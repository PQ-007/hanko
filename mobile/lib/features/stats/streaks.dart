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
int currentStreak(Iterable<DateTime> days, DateTime today) {
  final nums = days.map(_dayNumber).toSet();
  var cursor = _dayNumber(today);
  if (!nums.contains(cursor)) cursor -= 1;
  var streak = 0;
  while (nums.contains(cursor)) {
    streak += 1;
    cursor -= 1;
  }
  return streak;
}
