/// Word suggestions from OCR'd Japanese text, with no dictionary on the device
/// and no server of our own.
///
/// Japanese has no spaces, so a real tokenizer needs a dictionary (kuromoji,
/// MeCab: tens of MB). This instead splits on script boundaries, which is
/// where most content words start and end in running text:
///
/// - a kanji run plus the hiragana right after it (食べ + ました) is a verb or
///   adjective with its ending; Jisho resolves the conjugation to dictionary
///   form when the candidate is looked up (食べました → 食べる);
/// - a kanji run followed by a particle (日本語 + を) is a noun on its own;
/// - a katakana run of two or more characters is a loanword.
///
/// Hiragana-only words (ある, とても) are never suggested: without a dictionary
/// they can't be told apart from grammar. Those, and anything this gets wrong,
/// are what manual selection in the capture screen is for — suggestions are a
/// shortcut, never the only way in.
library;

enum _Script { kanji, hiragana, katakana, other }

_Script _scriptOf(int c) {
  // 々 (iteration mark) and 〆 behave as kanji inside a word.
  if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF) || c == 0x3005 || c == 0x3006) {
    return _Script.kanji;
  }
  if (c >= 0x3041 && c <= 0x309F) return _Script.hiragana;
  // ー (long vowel mark) and the half-width block count as katakana.
  if ((c >= 0x30A0 && c <= 0x30FF) || (c >= 0xFF66 && c <= 0xFF9F)) return _Script.katakana;
  return _Script.other;
}

/// Hiragana that, at the start of the run after a kanji word, mark it as a
/// noun followed by a particle rather than a word with okurigana. Kept to
/// characters that rarely begin an ending: か and と are left out because
/// 書かない and 落とす are far more common than a noun followed by か or と.
const _particles = {'は', 'が', 'を', 'に', 'で', 'も', 'の', 'へ', 'や'};

/// The longest ending kept after a kanji run. Long enough for 食べさせられた,
/// short enough that a following clause isn't swallowed whole.
const _maxEnding = 6;

class _Run {
  _Run(this.script, this.text);
  final _Script script;
  String text;
}

List<_Run> _runs(String line) {
  final runs = <_Run>[];
  for (final c in line.runes) {
    final s = _scriptOf(c);
    final ch = String.fromCharCode(c);
    if (runs.isNotEmpty && runs.last.script == s) {
      runs.last.text += ch;
    } else {
      runs.add(_Run(s, ch));
    }
  }
  return runs;
}

/// Candidate words in reading order, each once. Candidates are surface forms
/// as they appear in the text; dictionary forms come from the lookup.
List<String> suggestWords(Iterable<String> lines) {
  final seen = <String>{};
  final out = <String>[];
  void add(String w) {
    if (w.isNotEmpty && seen.add(w)) out.add(w);
  }

  for (final line in lines) {
    final runs = _runs(line);
    for (var i = 0; i < runs.length; i++) {
      final r = runs[i];
      switch (r.script) {
        case _Script.katakana:
          // A lone ー or a single katakana is noise (or a furigana scrap).
          if (r.text.replaceAll('ー', '').runes.length >= 2) add(r.text);
        case _Script.kanji:
          final next = i + 1 < runs.length ? runs[i + 1] : null;
          if (next == null || next.script != _Script.hiragana || _particles.contains(next.text[0])) {
            add(r.text);
          } else {
            add(r.text + _ending(next.text));
          }
        case _Script.hiragana:
        case _Script.other:
          break;
      }
    }
  }
  return out;
}

/// The okurigana part of a hiragana run: up to the first particle after the
/// first character, capped at [_maxEnding].
String _ending(String run) {
  final chars = run.split('');
  var end = chars.length;
  for (var i = 1; i < chars.length; i++) {
    if (_particles.contains(chars[i])) {
      end = i;
      break;
    }
  }
  if (end > _maxEnding) end = _maxEnding;
  return chars.take(end).join();
}

/// Whether a Jisho result is plausibly the word that was asked about, rather
/// than Jisho's fuzzy best guess at something else. The dictionary form of a
/// kanji word starts with the same kanji (食べました → 食べる); a katakana
/// word is its own dictionary form.
bool lookupMatches(String candidate, String dictionaryForm) {
  if (dictionaryForm.isEmpty) return false;
  final first = candidate.runes.first;
  if (_scriptOf(first) == _Script.katakana) return dictionaryForm == candidate;
  return dictionaryForm.runes.first == first;
}
