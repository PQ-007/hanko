/// Rules for kanji writing practice, kept free of ML Kit and Flutter so they
/// can be tested directly.
library;

/// Whether [s] contains a kanji — there is nothing to practise writing in a
/// kana-only word like ありがとう.
bool hasKanji(String s) => s.runes.any(
  (c) =>
      (c >= 0x4E00 && c <= 0x9FFF) ||
      (c >= 0x3400 && c <= 0x4DBF) ||
      c == 0x3005,
);

String _normalize(String s) => s.replaceAll(RegExp(r'\s'), '');

/// The recogniser's best guess that matches [term], or null.
///
/// The recogniser returns several guesses ranked by likelihood. A word counts
/// as written if any of them is the term: handwriting on a phone is messy,
/// and the second guess being right still means the strokes said the word.
/// Requiring the top guess would mark a correct but untidy 連帯 wrong because
/// 連滞 scored a little higher.
String? matchingCandidate(String term, Iterable<String> candidates) {
  final want = _normalize(term);
  for (final c in candidates) {
    if (_normalize(c) == want) return c;
  }
  return null;
}

/// How many of the recogniser's guesses to show after a miss — enough to see
/// what it read, not a wall of near-identical shapes.
const shownGuesses = 3;
