import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../audio/example_sentences.dart' show wordStem;

/// The word's example sentence on the back of a review card: one quiet line
/// of Japanese with the word picked out, the translations behind a tap — so
/// the card gains a line, not three.
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
            Text.rich(
              TextSpan(
                style: base,
                children: highlightSpans(e.ja, widget.term, TextStyle(color: hk.sealText, fontWeight: FontWeight.w600)),
              ),
              textAlign: TextAlign.center,
            ),
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

/// [sentence] split so the first use of [term] — or, conjugated, its stem
/// (食べ for 食べる) — carries [mark].
List<TextSpan> highlightSpans(String sentence, String term, TextStyle mark) {
  final t = term.trim();
  var at = t.isEmpty ? -1 : sentence.indexOf(t);
  var len = t.length;
  if (at < 0 && t.isNotEmpty) {
    final stem = wordStem(t);
    at = sentence.indexOf(stem);
    len = stem.length;
  }
  if (at < 0) return [TextSpan(text: sentence)];
  return [
    TextSpan(text: sentence.substring(0, at)),
    TextSpan(text: sentence.substring(at, at + len), style: mark),
    TextSpan(text: sentence.substring(at + len)),
  ];
}
