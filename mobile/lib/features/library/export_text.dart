import '../../models/library.dart';

// The deck .txt export, built on the phone. Same format as the web's
// /api/decks/[id]/txt (and the extension's original export): one line per
// word, `Front \t Back \t Tag`, importable into Anki as-is. Ports of
// web/src/lib/wordText.ts, so a deck exported from either client is identical.

String sanitizeFilename(String name) {
  final s = name.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]+'), '_');
  final cut = s.length > 60 ? s.substring(0, 60) : s;
  return cut.isEmpty ? 'deck' : cut;
}

/// ASCII-only like the web's `\w` (a JS regex without the /u flag), so tags
/// match what the web export produces for the same deck.
String sanitizeTag(String name) =>
    name.replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');

/// "term (reading)" when the reading adds information.
String frontText(Word w) =>
    w.reading != null && w.reading!.isNotEmpty && w.reading != w.term
        ? '${w.term} (${w.reading})'
        : w.term;

/// English meaning, then the Mongolian on its own line.
String backText(Word w) => [w.meaning ?? '', w.meaningMn ?? '']
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .join('\n');

/// Words oldest first, as the web route orders them.
String buildDeckTxt(String deckName, List<Word> words) {
  final tag = sanitizeTag(deckName);
  final sorted = [...words]..sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
  return sorted.map((w) {
    final back = backText(w).replaceAll('\t', ' ').replaceAll('\n', '<br>');
    return [frontText(w), back, tag].join('\t');
  }).join('\n');
}
