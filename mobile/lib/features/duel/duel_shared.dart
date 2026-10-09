import 'dart:math' as math;

import '../battle/rules.dart' show QuizOption;

// Pure helpers for duels between people (0030), ports of the web's
// duel/_lib/sharedQuestions.ts and the headToHead() in decks/_lib/social.ts —
// pinned by the same cases in duel_shared_test.dart.

/// One question of the set the server plans when a match starts
/// (duel_plan_questions): both players answer the same word with the same
/// four options in the same order.
class SharedQuestion {
  const SharedQuestion({required this.term, this.reading, required this.options, required this.answer});
  final String term;
  final String? reading;
  final List<String> options;

  /// Index of the right option.
  final int answer;
}

/// `matches.questions`, parsed rather than trusted: an older match has none,
/// and a malformed set must fall back to each player's own deck, not crash.
List<SharedQuestion>? parseQuestions(Object? raw) {
  if (raw is! List) return null;
  final out = <SharedQuestion>[];
  for (final q in raw) {
    if (q is! Map) continue;
    final term = q['term'], reading = q['reading'], options = q['options'], answer = q['answer'];
    if (term is! String ||
        options is! List ||
        options.length != 4 ||
        !options.every((o) => o is String) ||
        answer is! int ||
        answer < 0 ||
        answer > 3) {
      continue;
    }
    out.add(SharedQuestion(
      term: term,
      reading: reading is String ? reading : null,
      options: options.cast<String>(),
      answer: answer,
    ));
  }
  return out.isEmpty ? null : out;
}

/// The question for a round (1-based); wraps when a match outlasts the set.
SharedQuestion questionFor(List<SharedQuestion> qs, int roundNo) => qs[(math.max(1, roundNo) - 1) % qs.length];

/// The four options in the server's order.
List<QuizOption> quizFor(SharedQuestion q) => [
      for (var i = 0; i < q.options.length; i++)
        QuizOption(term: '${q.term}#$i', answerText: q.options[i], correct: i == q.answer),
    ];

// ---- Face-to-face record ------------------------------------------------------

enum MatchResult { win, loss, draw }

class MatchSummary {
  const MatchSummary(this.id, this.result, this.myHp, this.theirHp, this.abandoned, this.at);
  final String id;
  final MatchResult result;
  final int myHp, theirHp;
  final bool abandoned;
  final String at;
}

class HeadToHead {
  const HeadToHead({this.wins = 0, this.losses = 0, this.draws = 0, this.matches = const []});
  final int wins, losses, draws;

  /// Newest first.
  final List<MatchSummary> matches;

  int get total => wins + losses + draws;

  /// Oldest → newest, the last [n] results.
  List<MatchSummary> last([int n = 5]) => matches.take(n).toList().reversed.toList();
}

/// Your record against each opponent from your finished/abandoned matches
/// (rows as `matches` JSON). No winner is a draw; lobbies and live matches —
/// and a declined invitation, which never had a guest — don't count.
Map<String, HeadToHead> headToHead(List<Map<String, dynamic>> rows, String me) {
  final done = rows
      .where((m) => (m['status'] == 'finished' || m['status'] == 'abandoned') && m['guest_id'] != null)
      .toList()
    ..sort((a, b) => ((b['finished_at'] ?? b['created_at']) as String).compareTo((a['finished_at'] ?? a['created_at']) as String));
  final acc = <String, ({int w, int l, int d, List<MatchSummary> ms})>{};
  for (final m in done) {
    final iAmHost = m['host_id'] == me;
    if (!iAmHost && m['guest_id'] != me) continue;
    final other = (iAmHost ? m['guest_id'] : m['host_id']) as String;
    final winner = m['winner_id'] as String?;
    final result = winner == null ? MatchResult.draw : (winner == me ? MatchResult.win : MatchResult.loss);
    final rec = acc[other] ?? (w: 0, l: 0, d: 0, ms: <MatchSummary>[]);
    rec.ms.add(MatchSummary(
      m['id'] as String,
      result,
      ((iAmHost ? m['host_hp'] : m['guest_hp']) as num?)?.toInt() ?? 0,
      ((iAmHost ? m['guest_hp'] : m['host_hp']) as num?)?.toInt() ?? 0,
      m['status'] == 'abandoned',
      (m['finished_at'] ?? m['created_at']) as String,
    ));
    acc[other] = (
      w: rec.w + (result == MatchResult.win ? 1 : 0),
      l: rec.l + (result == MatchResult.loss ? 1 : 0),
      d: rec.d + (result == MatchResult.draw ? 1 : 0),
      ms: rec.ms,
    );
  }
  return {for (final e in acc.entries) e.key: HeadToHead(wins: e.value.w, losses: e.value.l, draws: e.value.d, matches: e.value.ms)};
}
