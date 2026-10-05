import '../writing/lesson.dart';
import '../writing/writing_rules.dart';
import 'rules.dart';

/// Monster Hunt's question types on mobile. The web asks only [meaning]; the
/// mobile hunt also asks the learner to write the word, so one fight
/// exercises both reading and the hand.
///
/// None of this touches the shared rules pinned by battle.fixture.json
/// (`rollEvent`, `buildQuiz`, the monster bag): [meaning] still uses
/// `buildQuiz` unchanged.
///
/// (A "pick the word from its meaning" and a "pick the word you hear" kind
/// were tried and dropped: they made the fight feel like a quiz menu rather
/// than one rhythm, without adding a skill the other two don't already work.)
enum QuestionKind {
  /// The word is shown; pick its meaning (the web's only question).
  meaning,

  /// Reading and meaning are shown; write the word's kanji, one at a time.
  write,
}

/// How often each kind comes up, relative to the other when both are
/// possible. Writing is slower, so it's the rarer of the two — and it hits
/// harder ([writeDamageBonus]).
const kindWeights = {
  QuestionKind.meaning: 3,
  QuestionKind.write: 2,
};

/// A written answer hits this much harder than a picked one.
const writeDamageBonus = 1.5;

/// Writing more kanji than this in one battle question would stall the
/// fight; such words are asked by meaning.
const maxWriteKanji = 3;

/// Time allowed per kanji on a writing question. A choice question gets the
/// shared [questionTimeLimitMs].
const writeMsPerKanji = 12000;

/// The kinds [w] can be asked as. Writing needs kanji to write, not too many,
/// and the handwriting recogniser to be ready ([canWrite]).
Set<QuestionKind> eligibleKinds(QuizWord w, {required bool canWrite}) {
  final kanji = kanjiOf(w.term).length;
  return {
    QuestionKind.meaning,
    if (canWrite && kanji > 0 && kanji <= maxWriteKanji && hasKanji(w.term)) QuestionKind.write,
  };
}

/// Picks one of [eligible], weighted by [kindWeights], using one [rand] draw.
/// Kinds outside [allowed] are never picked (tests pin a single kind).
QuestionKind pickKind(Set<QuestionKind> eligible, Rand rand, {Set<QuestionKind>? allowed}) {
  final kinds = [
    for (final k in QuestionKind.values)
      if (eligible.contains(k) && (allowed == null || allowed.contains(k))) k,
  ];
  if (kinds.isEmpty) return QuestionKind.meaning;
  final total = kinds.fold<int>(0, (s, k) => s + kindWeights[k]!);
  var roll = rand() * total;
  for (final k in kinds) {
    roll -= kindWeights[k]!;
    if (roll < 0) return k;
  }
  return kinds.last;
}

/// The time a question allows.
int timeLimitFor(QuestionKind kind, String term) =>
    kind == QuestionKind.write ? writeMsPerKanji * kanjiOf(term).length : questionTimeLimitMs;

/// The speed tier for a correct answer, judged against that question's own
/// time limit — a written word answered in half its time is as fast as a
/// picked one answered in half of ten seconds.
String speedFor(int elapsedMs, int limitMs) =>
    ratingForElapsed((elapsedMs * questionTimeLimitMs / limitMs).round());
