import '../../core/dictionary.dart';
import '../../models/library.dart';
import 'segment.dart';

/// One word on the capture review screen.
class CaptureItem {
  CaptureItem({required this.draft, required this.found});

  WordDraft draft;

  /// False when the dictionary had nothing that matched: the term is kept as
  /// photographed, with blank fields to fill in by hand.
  final bool found;
  bool selected = true;
  bool inDeck = false;
}

/// At most this many Jisho requests at once: a page of thirty words shouldn't
/// look like a burst of thirty to a free public API.
const _concurrency = 4;

/// Looks up every chosen term and turns it into a draft — dictionary form,
/// reading, English and Mongolian when Jisho recognises it, the term as
/// photographed with blank fields when it doesn't (or there's no connection).
///
/// Two surface forms of one word (食べた, 食べます) collapse into one item, in
/// the order they were chosen.
Future<List<CaptureItem>> resolveCapture(
  List<String> terms,
  Dictionary dictionary, {
  void Function(int done, int total)? onProgress,
}) async {
  final results = List<CaptureItem?>.filled(terms.length, null);
  var next = 0, done = 0;

  Future<void> worker() async {
    while (next < terms.length) {
      final i = next++;
      results[i] = await _resolveOne(terms[i], dictionary);
      onProgress?.call(++done, terms.length);
    }
  }

  await Future.wait([for (var w = 0; w < _concurrency; w++) worker()]);

  final seen = <String>{};
  return [
    for (final item in results)
      if (item != null && seen.add(item.draft.term)) item,
  ];
}

Future<CaptureItem> _resolveOne(String term, Dictionary dictionary) async {
  final r = await dictionary.lookup(term);
  if (!lookupMatches(term, r.word)) {
    return CaptureItem(draft: WordDraft(term: term), found: false);
  }
  final mn = r.meaning.isEmpty ? '' : await dictionary.translate(r.meaning);
  return CaptureItem(
    found: true,
    draft: WordDraft(
      term: r.word,
      reading: r.reading.isEmpty || r.reading == r.word ? null : r.reading,
      meaning: r.meaning.isEmpty ? null : r.meaning,
      meaningMn: mn.isEmpty ? null : mn,
    ),
  );
}
