import '../../models/library.dart';
import '../audio/example_sentences.dart';

/// "Add example sentences" for a whole deck: every word without a sentence
/// gets a Tatoeba suggestion, its Mongolian translated from the English.
/// Words that already have one are never fetched and never written — and the
/// save itself only writes a word whose sentence is still empty
/// (`Repository.saveExampleIfEmpty`), so a sentence typed meanwhile on
/// another device survives too.
///
/// A port of web/src/app/decks/_lib/fillExamples.ts, pinned by the same cases
/// (fill_examples_test.dart / fillExamples.test.ts). Pure, with the network
/// and the database injected.

/// At most this many words in flight: polite to a free API, still quick.
const fillConcurrency = 3;

typedef FillResult = ({int added, int missing, int skipped});

Future<FillResult> fillExamples(
  List<({String id, String term})> words, {
  required Future<Example?> Function(String term) find,
  required Future<String> Function(String text) translate,
  required Future<bool> Function(String wordId, WordExample e) save,
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
  int concurrency = fillConcurrency,
}) async {
  var added = 0, missing = 0, skipped = 0;
  var next = 0, done = 0;
  Future<void> worker() async {
    while (next < words.length && !(cancelled?.call() ?? false)) {
      final w = words[next++];
      final hit = await find(w.term);
      if (hit == null) {
        missing++;
      } else {
        final mn = await translate(hit.en);
        bool saved;
        try {
          saved = await save(w.id, WordExample(ja: hit.ja, en: hit.en, mn: mn, furigana: hit.furigana));
        } catch (_) {
          saved = false;
        }
        if (saved) {
          added++;
        } else {
          skipped++;
        }
      }
      onProgress?.call(++done, words.length);
    }
  }

  await Future.wait([for (var i = 0; i < (concurrency < 1 ? 1 : concurrency); i++) worker()]);
  return (added: added, missing: missing, skipped: skipped);
}
