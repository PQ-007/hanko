import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/review/srs_preview.dart';

/// These expectations are transcribed from behaviour actually observed against
/// Postgres running supabase/migrations/0009_review_card.sql — not from reading
/// the Dart source back to itself. If the migration's constants change, these
/// fail, which is the point: the preview is a mirror and mirrors drift.
void main() {
  Preview p({
    required String state,
    required String rating,
    int step = 0,
    int interval = 0,
    int reps = 0,
    double ease = 2.5,
  }) =>
      previewNext(
        state: state,
        learningStep: step,
        intervalDays: interval,
        repetitions: reps,
        easeFactor: ease,
        rating: rating,
      );

  group('new / learning cards come back in minutes', () {
    test('a new card: Again and Hard both sit on the first step (1 min)', () {
      expect(p(state: 'new', rating: 'again').value, 1);
      expect(p(state: 'new', rating: 'hard').value, 1);
      expect(p(state: 'new', rating: 'again').unit, PreviewUnit.minutes);
    });

    test('a new card answered Good advances to the 10 min step', () {
      final r = p(state: 'new', rating: 'good');
      expect(r.unit, PreviewUnit.minutes);
      expect(r.value, 10);
    });

    test('Hard on step 1 repeats that step (10 min), it is not Again', () {
      // The bug this guards: Hard used to collapse back to the first step,
      // making it identical to Again.
      expect(p(state: 'learning', step: 1, rating: 'hard').value, 10);
      expect(p(state: 'learning', step: 1, rating: 'again').value, 1);
    });

    test('Good on the last step graduates to 1 day; Easy jumps to 4', () {
      final good = p(state: 'learning', step: 1, rating: 'good');
      expect(good.unit, PreviewUnit.days);
      expect(good.value, 1);

      final easy = p(state: 'new', rating: 'easy');
      expect(easy.unit, PreviewUnit.days);
      expect(easy.value, 4);
    });
  });

  group('review cards follow SM-2', () {
    test('a lapse drops to relearning, previewed in minutes not days', () {
      final r = p(state: 'review', rating: 'again', interval: 25, reps: 5);
      expect(r.unit, PreviewUnit.minutes);
      expect(r.value, 10);
    });

    test('Good on a mature card grows by the ease factor', () {
      // interval 10 x ease 2.5 = 25. The server then fuzzes +/-5%, which is
      // deliberately not previewed.
      final r = p(state: 'review', rating: 'good', interval: 10, reps: 5);
      expect(r.unit, PreviewUnit.days);
      expect(r.value, 25);
    });

    test('a better rating always buys strictly more time', () {
      final hard = p(state: 'review', rating: 'hard', interval: 10, reps: 5);
      final good = p(state: 'review', rating: 'good', interval: 10, reps: 5);
      final easy = p(state: 'review', rating: 'easy', interval: 10, reps: 5);
      expect(hard.value < good.value, isTrue);
      expect(good.value < easy.value, isTrue);
    });

    test('a passing answer never leaves the interval unchanged, even at min ease', () {
      // At ease 1.3 the multiplier alone would round 1 day back to 1 day; the
      // graduated floor is what stops the card getting stuck.
      final r = p(state: 'review', rating: 'good', interval: 1, reps: 5, ease: 1.3);
      expect(r.value > 1, isTrue);
    });
  });

  group('relearning', () {
    test('Again repeats the relearn step, passing returns to day scale', () {
      expect(p(state: 'relearning', rating: 'again', interval: 1).value, 10);
      final good = p(state: 'relearning', rating: 'good', interval: 1);
      expect(good.unit, PreviewUnit.days);
      expect(good.value, 1);
    });
  });

  group('formatting', () {
    test('switches units at 30 days and 365 days', () {
      expect(formatPreview(const Preview(PreviewUnit.minutes, 10)), '10 мин');
      expect(formatPreview(const Preview(PreviewUnit.days, 6)), '6 өдөр');
      expect(formatPreview(const Preview(PreviewUnit.days, 60)), '2 сар');
      expect(formatPreview(const Preview(PreviewUnit.days, 730)), '2 жил');
    });

    test('months and years keep a decimal so distinct schedules stay distinct', () {
      // 75 and 102 days both round to "3 сар" without this, making two
      // different buttons look identical.
      expect(formatPreview(const Preview(PreviewUnit.days, 75)),
          isNot(formatPreview(const Preview(PreviewUnit.days, 102))));
    });
  });
}
