import '../../core/dictionary.dart';

// Which add-word fields a dictionary match may fill — a port of the web's
// web/src/app/decks/_lib/addWord.ts, pinned by the same cases in both tests.
//
// The sheet looks the term up as it changes (typed or drawn), so a match
// arrives many times per word. It may write into a field that is empty or
// that it filled itself last time; once the user has typed into a field, that
// field is theirs and later matches leave it alone. Without the second half,
// drawing 生 then 活 would leave 生's reading under 生活.

class WordFields {
  const WordFields({this.term = '', this.reading = '', this.meaning = '', this.meaningMn = ''});
  final String term;
  final String reading;
  final String meaning;
  final String meaningMn;

  WordFields copyWith({String? term, String? reading, String? meaning, String? meaningMn}) =>
      WordFields(
        term: term ?? this.term,
        reading: reading ?? this.reading,
        meaning: meaning ?? this.meaning,
        meaningMn: meaningMn ?? this.meaningMn,
      );

  String operator [](AutoKey k) => switch (k) {
    AutoKey.reading => reading,
    AutoKey.meaning => meaning,
    AutoKey.meaningMn => meaningMn,
  };

  @override
  bool operator ==(Object other) =>
      other is WordFields &&
      other.term == term &&
      other.reading == reading &&
      other.meaning == meaning &&
      other.meaningMn == meaningMn;

  @override
  int get hashCode => Object.hash(term, reading, meaning, meaningMn);
}

/// Fields whose current value came from a lookup or a translation, not the user.
enum AutoKey { reading, meaning, meaningMn }

/// Fills the fields still open to the machine from [m]. The term is never
/// touched — rewriting what is under the user's caret mid-word is worse than a
/// conjugated form, which accepting a match (the keyboard's next/done) still
/// fixes.
///
/// When the English changes, a machine-filled Mongolian meaning is cleared
/// rather than left describing the old word; the caller re-translates.
({WordFields fields, Set<AutoKey> auto, bool meaningChanged}) autofill(
  WordFields f,
  Set<AutoKey> auto,
  LookupResult m,
) {
  final next = {...auto};
  bool open(AutoKey k) => f[k].trim().isEmpty || auto.contains(k);
  var fields = f;
  if (open(AutoKey.reading)) {
    fields = fields.copyWith(reading: m.reading);
    next.add(AutoKey.reading);
  }
  if (open(AutoKey.meaning)) {
    fields = fields.copyWith(meaning: m.meaning);
    next.add(AutoKey.meaning);
  }
  final meaningChanged = fields.meaning != f.meaning;
  if (meaningChanged && open(AutoKey.meaningMn)) {
    fields = fields.copyWith(meaningMn: '');
    next.add(AutoKey.meaningMn);
  }
  return (fields: fields, auto: next, meaningChanged: meaningChanged);
}

/// The match a field set came from, if any — the one the list shows as picked.
LookupResult? pickedMatch(WordFields f, List<LookupResult> matches) {
  final term = f.term.trim();
  final reading = f.reading.trim();
  return matches.where((m) => m.word == term && m.reading == reading).firstOrNull;
}
