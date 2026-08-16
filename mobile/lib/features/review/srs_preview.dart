import 'dart:math' as math;

/// Rating-button previews: "what will this button cost me?"
///
/// ⚠️ THIS IS A MIRROR, NOT THE SCHEDULER. The authoritative implementation is
/// `review_card()` in supabase/migrations/0009_review_card.sql, and the web
/// app's copy is `previewNext()` in web/src/lib/srs.ts. All three must agree.
/// If you change one, change the others — the constants below are duplicated
/// from the migration on purpose, so a mismatch is a visible diff rather than a
/// silent behavioural drift.
///
/// Nothing here decides anything: the app sends a rating to the server and the
/// server returns the real schedule. This exists purely so a button can say
/// "10 мин" instead of lying about a day-scale interval on a card that is still
/// in the learning steps.

/// Must match v_learn_steps / v_relearn_steps in 0009_review_card.sql.
const learnStepsMinutes = [1, 10];
const relearnStepsMinutes = [10];
const _graduatingInterval = 1;
const _easyInterval = 4;
const _minEase = 1.3;
const _hardMultiplier = 1.2;
const _easyBonus = 1.3;

enum PreviewUnit { minutes, days }

class Preview {
  const Preview(this.unit, this.value);
  final PreviewUnit unit;
  final int value;
}

/// [state] is the card's server-side state: new | learning | review | relearning.
Preview previewNext({
  required String state,
  required int learningStep,
  required int intervalDays,
  required int repetitions,
  required double easeFactor,
  required String rating,
}) {
  if (state == 'new' || state == 'learning') {
    switch (rating) {
      case 'again':
        return Preview(PreviewUnit.minutes, learnStepsMinutes[0]);
      case 'hard':
        // Hard repeats the step the card is sitting on.
        final i = math.min(learningStep, learnStepsMinutes.length - 1);
        return Preview(PreviewUnit.minutes, learnStepsMinutes[i]);
      case 'easy':
        return const Preview(PreviewUnit.days, _easyInterval);
      default: // good
        final next = learningStep + 1;
        return next >= learnStepsMinutes.length
            ? const Preview(PreviewUnit.days, _graduatingInterval)
            : Preview(PreviewUnit.minutes, learnStepsMinutes[next]);
    }
  }

  if (state == 'relearning') {
    return rating == 'again'
        ? Preview(PreviewUnit.minutes, relearnStepsMinutes[0])
        : Preview(PreviewUnit.days, math.max(1, intervalDays));
  }

  // Review state: a lapse drops into relearning, anything else follows SM-2.
  if (rating == 'again') {
    return Preview(PreviewUnit.minutes, relearnStepsMinutes[0]);
  }

  final q = switch (rating) { 'hard' => 3, 'good' => 4, _ => 5 };
  final ease = math.max(
    _minEase,
    easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)),
  );

  final reps = repetitions + 1;
  int interval;
  if (reps == 1) {
    interval = rating == 'easy' ? 4 : 1;
  } else if (reps == 2) {
    interval = switch (rating) { 'hard' => 3, 'easy' => 8, _ => 6 };
  } else {
    final factor = switch (rating) {
      'hard' => _hardMultiplier,
      'easy' => ease * _easyBonus,
      _ => ease,
    };
    // Easy rounds up so it can't collide with Good on short intervals.
    final grown = rating == 'easy'
        ? (intervalDays * factor).ceil()
        : (intervalDays * factor).round();
    // A passing answer never leaves the card on the same interval, and the
    // floor is graduated by rating so a better answer always buys strictly
    // more time even at low ease.
    final floor = intervalDays + switch (rating) { 'hard' => 1, 'easy' => 3, _ => 2 };
    interval = math.max(floor, grown);
  }

  // The server also applies ±5% fuzz, deliberately not previewed — showing
  // "24 өдөр" and then scheduling 25 would read as a bug.
  return Preview(PreviewUnit.days, interval);
}

String formatPreview(Preview p) {
  if (p.unit == PreviewUnit.minutes) return '${p.value} мин';
  if (p.value < 30) return '${p.value} өдөр';
  if (p.value < 365) return '${_round1(p.value / 30)} сар';
  return '${_round1(math.max(1, p.value / 365))} жил';
}

String _round1(double n) {
  final r = (n * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}
