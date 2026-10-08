import 'writing_rules.dart';

/// How a kanji is practised, from most to least help — the Duolingo-style
/// ladder: trace it, write it with some strokes shown, write it from memory.
/// [word] then asks for the whole word, one kanji at a time.
enum StepKind { trace, partial, blank, word }

class LessonStep {
  const LessonStep(this.kind, this.wordIndex, {this.char});

  final StepKind kind;

  /// Which of the lesson's words this step belongs to.
  final int wordIndex;

  /// The kanji practised, for the three single-kanji steps.
  final String? char;

  @override
  String toString() =>
      char == null ? '${kind.name}#$wordIndex' : '${kind.name}:$char';
}

/// At most this many new kanji are taught in one lesson.
const newKanjiPerLesson = 10;

/// And at most this many words, so revising known kanji doesn't run on.
const wordsPerLesson = 10;

/// How many of `terms[from…]` the next lesson takes: words in order until the
/// next one would push the new kanji (not [learned], not already in this
/// lesson) past [newKanjiPerLesson], or the lesson has [wordsPerLesson]
/// words. Always at least one word, so a single word with more new kanji than
/// the cap still gets its lesson. A port of `lessonSize` in lesson.ts.
int lessonSize(List<String> terms, int from, {Set<String> learned = const {}}) {
  final fresh = <String>{};
  var n = 0;
  for (var i = from; i < terms.length && n < wordsPerLesson; i++) {
    final add = {
      for (final k in kanjiOf(terms[i]))
        if (!learned.contains(k) && !fresh.contains(k)) k,
    };
    if (n > 0 && fresh.length + add.length > newKanjiPerLesson) break;
    fresh.addAll(add);
    n++;
  }
  return n;
}

/// The kanji in [term] in order, kana and other characters left out.
List<String> kanjiOf(String term) => [
  for (final r in term.runes)
    if (hasKanji(String.fromCharCode(r))) String.fromCharCode(r),
];

/// The kanji positions in [term] (indexes into its characters), which the
/// word step asks for one at a time; the kana around them are given.
List<int> kanjiPositions(String term) {
  final chars = term.runes.map(String.fromCharCode).toList();
  return [
    for (var i = 0; i < chars.length; i++)
      if (hasKanji(chars[i])) i,
  ];
}

/// The steps for a lesson over [terms].
///
/// A kanji not yet [learned] gets the full ladder the first time it appears
/// in the lesson; one already learned (in this lesson or an earlier one)
/// gets none, and is only asked for inside its word. Each word ends with the
/// word step — unless the word is a single kanji that was just taught, which
/// would ask the same thing twice in a row.
List<LessonStep> planLesson(
  List<String> terms, {
  Set<String> learned = const {},
}) {
  final taught = <String>{};
  final steps = <LessonStep>[];
  for (var w = 0; w < terms.length; w++) {
    final kanji = kanjiOf(terms[w]);
    var taughtHere = false;
    for (final k in kanji) {
      if (learned.contains(k) || !taught.add(k)) continue;
      taughtHere = true;
      steps
        ..add(LessonStep(StepKind.trace, w, char: k))
        ..add(LessonStep(StepKind.partial, w, char: k))
        ..add(LessonStep(StepKind.blank, w, char: k));
    }
    final singleJustTaught = taughtHere && terms[w].runes.length == 1;
    if (kanji.isNotEmpty && !singleJustTaught) {
      steps.add(LessonStep(StepKind.word, w));
    }
  }
  return steps;
}

/// Strokes shown on the "some strokes" step: the first half, rounded down,
/// so the second half — usually where the kanji's distinctive part is — has
/// to come from the learner. A one-stroke kanji shows none.
int partialStrokes(int count) => count ~/ 2;

/// Orders candidate words so the ones that still have something to teach come
/// first: a lesson of only already-learned kanji is a review, which is fine,
/// but not when there are new kanji waiting.
List<T> newKanjiFirst<T>(
  List<T> words,
  String Function(T) termOf,
  Set<String> learned,
) {
  bool hasNew(T w) => kanjiOf(termOf(w)).any((k) => !learned.contains(k));
  return [...words.where(hasNew), ...words.where((w) => !hasNew(w))];
}

/// Every kanji in [terms], each once, in the order they first appear — the
/// grid the learner picks from.
List<String> kanjiInOrder(Iterable<String> terms) {
  final seen = <String>{};
  return [
    for (final t in terms)
      for (final k in kanjiOf(t))
        if (seen.add(k)) k,
  ];
}

/// The words that teach [kanji]: for each, the first word containing it, each
/// word once. Picking 連 and 帯 from a deck with 連帯 gives just 連帯 — one
/// word covers both, so neither is taught through a second word for nothing.
List<T> wordsForKanji<T>(
  List<String> kanji,
  List<T> words,
  String Function(T) termOf,
) {
  final out = <T>[];
  for (final k in kanji) {
    if (out.any((w) => termOf(w).contains(k))) continue;
    for (final w in words) {
      if (termOf(w).contains(k)) {
        out.add(w);
        break;
      }
    }
  }
  return out;
}
