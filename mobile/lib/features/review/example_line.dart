import 'package:flutter/material.dart';

import '../../core/furigana.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../audio/example_sentences.dart' show wordStem;

/// The word's example sentence on the back of a review card: one quiet line
/// of Japanese with the word picked out and furigana over its kanji (when
/// the sentence came with a reading — one the user wrote has none), the
/// translations behind a tap — so the card gains a line, not three.
///
/// Give it a key per card, so a new card starts with the translation hidden.
class ExampleLine extends StatefulWidget {
  const ExampleLine({super.key, required this.example, required this.term});

  final WordExample example;
  final String term;

  @override
  State<ExampleLine> createState() => _ExampleLineState();
}

class _ExampleLineState extends State<ExampleLine> {
  var _open = false;

  /// Plain text when there's no reading; otherwise each unit is a little
  /// column — reading over text — inline, so the line still wraps and
  /// centres like text. Flutter has no ruby of its own.
  Widget _sentence(WordExample e, TextStyle base, TextStyle mark, Color readingColor) {
    final units = rubyUnits(e.ja, e.furigana);
    if (units.every((u) => u.reading.isEmpty)) {
      return Text.rich(
        TextSpan(style: base, children: highlightSpans(e.ja, widget.term, mark)),
        textAlign: TextAlign.center,
      );
    }
    final range = highlightRange(e.ja, widget.term);
    final readingStyle = TextStyle(fontSize: 9.5, height: 1.2, color: readingColor);
    var at = 0;
    final spans = <InlineSpan>[];
    for (final u in units) {
      final start = at;
      at += u.text.length;
      final marked = range != null && start < range.$2 && at > range.$1;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A blank reading keeps every unit the same height.
            Text(u.reading.isEmpty ? ' ' : u.reading, style: readingStyle),
            Text(u.text, style: marked ? base.merge(mark) : base),
          ],
        ),
      ));
    }
    return Text.rich(TextSpan(children: spans), textAlign: TextAlign.center);
  }

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final e = widget.example;
    final hasTranslation = e.mn.isNotEmpty || e.en.isNotEmpty;
    final base = TextStyle(fontSize: 15, height: 1.5, color: hk.inkSoft);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: hasTranslation ? () => setState(() => _open = !_open) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            _sentence(e, base, TextStyle(color: hk.sealText, fontWeight: FontWeight.w600), hk.inkMute),
            if (hasTranslation && !_open)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(T.exampleShowTranslation, style: TextStyle(fontSize: 11, color: hk.inkMute)),
              ),
            if (_open) ...[
              if (e.mn.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(e.mn, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: hk.ink)),
                ),
              if (e.en.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(e.en, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: hk.inkMute)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where [sentence] uses [term] — the word itself, or, conjugated, its stem
/// (食べ for 食べる): (start, end), or null. Same rule as highlightRange in
/// web/src/lib/examples.ts.
(int, int)? highlightRange(String sentence, String term) {
  final t = term.trim();
  if (t.isEmpty) return null;
  var at = sentence.indexOf(t);
  var len = t.length;
  if (at < 0) {
    final stem = wordStem(t);
    at = sentence.indexOf(stem);
    len = stem.length;
  }
  return at < 0 ? null : (at, at + len);
}

/// [sentence] split so the first use of [term] carries [mark].
List<TextSpan> highlightSpans(String sentence, String term, TextStyle mark) {
  final r = highlightRange(sentence, term);
  if (r == null) return [TextSpan(text: sentence)];
  return [
    TextSpan(text: sentence.substring(0, r.$1)),
    TextSpan(text: sentence.substring(r.$1, r.$2), style: mark),
    TextSpan(text: sentence.substring(r.$2)),
  ];
}
