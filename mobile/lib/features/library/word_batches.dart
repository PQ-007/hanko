import '../../models/library.dart';

// Ordering and narrowing a deck's word list, and finding what was added
// together — so a batch pushed into the wrong deck can be found and undone
// without hunting for its words one by one.
//
// A batch needs no column of its own. `date_added` defaults to now(), which
// Postgres fixes at the start of the transaction, and the camera saves a
// whole capture in one insert (Repository.addWords; the offline outbox sends
// each deck's queue as one insert too). So every word of a capture carries
// the identical timestamp, to the microsecond, while words added by hand or
// from the extension arrive one insert at a time.

enum WordSort { newest, oldest, alphabetical }

enum AddedWithin { any, today, week }

List<Word> sortWords(List<Word> words, WordSort sort) {
  final out = [...words];
  switch (sort) {
    case WordSort.newest:
      out.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    case WordSort.oldest:
      out.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
    case WordSort.alphabetical:
      // By reading where there is one, so kanji words fall among the kana
      // in the order a Japanese dictionary would put them.
      String key(Word w) => (w.reading?.isNotEmpty ?? false) ? w.reading! : w.term;
      out.sort((a, b) => key(a).compareTo(key(b)));
  }
  return out;
}

/// Words added since local midnight today, or in the last seven days.
List<Word> addedWithin(List<Word> words, AddedWithin within, DateTime now) {
  if (within == AddedWithin.any) return words;
  final today = DateTime(now.year, now.month, now.day);
  final since = within == AddedWithin.today ? today : today.subtract(const Duration(days: 6));
  return [for (final w in words) if (!w.dateAdded.toLocal().isBefore(since)) w];
}

/// Words that went in together, newest batch first.
class WordBatch {
  const WordBatch(this.at, this.words);
  final DateTime at;
  final List<Word> words;
}

/// Every group of two or more words sharing one `date_added`, newest first.
/// A single word is not a batch: deleting it is one tap already.
List<WordBatch> wordBatches(List<Word> words) {
  final byTime = <DateTime, List<Word>>{};
  for (final w in words) {
    (byTime[w.dateAdded] ??= []).add(w);
  }
  final out = [
    for (final e in byTime.entries)
      if (e.value.length >= 2) WordBatch(e.key, e.value),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return out;
}

/// The batch worth offering to undo: the deck's most recent addition, if it
/// was a batch and it happened within [recent]. Older than that it is just
/// part of the deck, and the card would be clutter.
WordBatch? latestBatch(
  List<Word> words,
  DateTime now, {
  Duration recent = const Duration(days: 1),
}) {
  if (words.isEmpty) return null;
  final newest = words.map((w) => w.dateAdded).reduce((a, b) => a.isAfter(b) ? a : b);
  if (now.difference(newest) > recent) return null;
  final batch = [for (final w in words) if (w.dateAdded == newest) w];
  return batch.length >= 2 ? WordBatch(newest, batch) : null;
}
