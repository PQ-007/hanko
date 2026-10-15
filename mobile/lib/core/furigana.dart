/// Furigana for example sentences (0032), from Tatoeba's reading markup:
/// "[私|わたし]は[羊|ひつじ]の[群|むれ]を[見|み]た。" — a bracket per word, one
/// reading per kanji when they split cleanly ("[勉強|べん|きょう]"), else one
/// over the whole word ("[今日|きょう]"). No tokenizer, on purpose.
///
/// A port of parseFurigana / plainOf / rubyUnits in web/src/lib/examples.ts,
/// pinned by the same cases (word_example_test.dart / examples.test.ts).
library;

class RubyUnit {
  const RubyUnit(this.text, [this.reading = '']);
  final String text;

  /// '' for text that needs none (kana, punctuation).
  final String reading;

  @override
  bool operator ==(Object other) => other is RubyUnit && other.text == text && other.reading == reading;

  @override
  int get hashCode => Object.hash(text, reading);

  @override
  String toString() => reading.isEmpty ? text : '$text($reading)';
}

/// The markup as units to draw, or null when it's malformed.
List<RubyUnit>? parseFurigana(String markup) {
  final out = <RubyUnit>[];
  final chars = markup.runes.map(String.fromCharCode).toList();
  var i = 0;
  while (i < chars.length) {
    final ch = chars[i];
    if (ch == ']') return null;
    if (ch != '[') {
      out.add(RubyUnit(ch));
      i++;
      continue;
    }
    final end = chars.indexOf(']', i);
    if (end < 0) return null;
    final parts = chars.sublist(i + 1, end).join().split('|');
    final base = parts.first;
    final readings = parts.sublist(1);
    if (base.isEmpty || base.contains('[') || readings.any((r) => r.isEmpty)) return null;
    final baseChars = base.runes.map(String.fromCharCode).toList();
    if (readings.length > 1 && readings.length == baseChars.length) {
      for (var k = 0; k < baseChars.length; k++) {
        out.add(RubyUnit(baseChars[k], readings[k] == baseChars[k] ? '' : readings[k]));
      }
    } else {
      final reading = readings.join();
      out.add(RubyUnit(base, reading == base ? '' : reading));
    }
    i = end + 1;
  }
  return out;
}

/// The plain sentence a reading describes ('' when malformed).
String plainOf(String markup) => parseFurigana(markup)?.map((u) => u.text).join() ?? '';

/// What to draw for [ja]: its reading's units when [furigana] describes it
/// exactly, else one unit per character with no reading — a sentence the
/// user edited or wrote has no reading to trust.
List<RubyUnit> rubyUnits(String ja, String? furigana) {
  final units = furigana == null || furigana.isEmpty ? null : parseFurigana(furigana);
  if (units != null && units.map((u) => u.text).join() == ja) return units;
  return [for (final c in ja.runes) RubyUnit(String.fromCharCode(c))];
}

/// [furigana] if it still describes [ja], else null.
String? furiganaFor(String ja, String? furigana) {
  final f = furigana?.trim() ?? '';
  return f.isNotEmpty && plainOf(f) == ja.trim() ? f : null;
}
