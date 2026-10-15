/// Folder, deck and word rows as the library screens use them.
///
/// The SRS columns on `words` (repetitions, interval_days, due_at) are the
/// compatibility mirror `review_card()` still writes (0021_fsrs.sql). They're
/// what the web's grade chart and stats read, so mobile reads the same ones —
/// the two clients can't grade a word differently.
library;

import '../core/furigana.dart' show furiganaFor;

class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Null for a root folder. A parent that's been deleted (or isn't visible)
  /// is treated as root too — see 0024_mobile_parity.sql.
  final String? parentId;
  final DateTime createdAt;

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        parentId: j['parent_id'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class Deck {
  const Deck({required this.id, required this.name, this.folderId});

  final String id;
  final String name;
  final String? folderId;

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        folderId: j['folder_id'] as String?,
      );
}

class Word {
  const Word({
    required this.id,
    required this.deckId,
    required this.term,
    this.reading,
    this.meaning,
    this.meaningMn,
    this.audioPath,
    this.example,
    required this.dateAdded,
    this.repetitions = 0,
    this.intervalDays = 0,
    this.dueAt,
    this.lastReviewedAt,
    this.deckName,
  });

  final String id;
  final String deckId;
  final String term;
  final String? reading;
  final String? meaning;
  final String? meaningMn;
  final String? audioPath;

  /// The saved example sentence (0031), null when the word has none.
  final WordExample? example;
  final DateTime dateAdded;
  final int repetitions;
  final int intervalDays;
  final DateTime? dueAt;
  final DateTime? lastReviewedAt;

  /// Only set on search results, which join the deck name in.
  final String? deckName;

  Word withAudioPath(String path) => Word(
        id: id,
        deckId: deckId,
        term: term,
        reading: reading,
        meaning: meaning,
        meaningMn: meaningMn,
        audioPath: path,
        example: example,
        dateAdded: dateAdded,
        repetitions: repetitions,
        intervalDays: intervalDays,
        dueAt: dueAt,
        lastReviewedAt: lastReviewedAt,
        deckName: deckName,
      );

  factory Word.fromJson(Map<String, dynamic> j) {
    final deck = j['deck'];
    return Word(
      id: j['id'] as String,
      deckId: j['deck_id'] as String,
      term: j['term'] as String? ?? '',
      reading: j['reading'] as String?,
      meaning: j['meaning'] as String?,
      meaningMn: j['meaning_mn'] as String?,
      audioPath: j['audio_path'] as String?,
      example: WordExample.fromRow(j),
      dateAdded: DateTime.tryParse(j['date_added'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      repetitions: (j['repetitions'] as num?)?.toInt() ?? 0,
      intervalDays: (j['interval_days'] as num?)?.toInt() ?? 0,
      dueAt: DateTime.tryParse(j['due_at'] as String? ?? ''),
      lastReviewedAt: DateTime.tryParse(j['last_reviewed_at'] as String? ?? ''),
      deckName: deck is Map ? deck['name'] as String? : null,
    );
  }
}

enum Grade {
  newWord('Шинэ'),
  f('F'),
  d('D'),
  c('C'),
  b('B'),
  a('A');

  const Grade(this.label);
  final String label;

  bool get mastered => this == a || this == b;
}

/// Mirror of `gradeFor()` in web/src/lib/srs.ts. Pinned against the same
/// boundaries by test/library_test.dart.
Grade gradeFor({required int repetitions, required int intervalDays}) {
  if (repetitions == 0) return Grade.newWord;
  if (intervalDays <= 1) return Grade.f;
  if (intervalDays <= 6) return Grade.d;
  if (intervalDays <= 21) return Grade.c;
  if (intervalDays <= 60) return Grade.b;
  return Grade.a;
}

Grade gradeOfWord(Word w) =>
    gradeFor(repetitions: w.repetitions, intervalDays: w.intervalDays);

/// One row of `review_stats()` (0024). Percentages are null when there was
/// nothing to measure in the window, which is not the same as 0%.
class ReviewStats {
  const ReviewStats({
    required this.total,
    required this.correct,
    this.accuracyPct,
    required this.reviewTotal,
    required this.reviewCorrect,
    this.retentionPct,
  });

  final int total;
  final int correct;
  final double? accuracyPct;
  final int reviewTotal;
  final int reviewCorrect;
  final double? retentionPct;

  factory ReviewStats.fromJson(Map<String, dynamic> j) => ReviewStats(
        total: (j['total'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        accuracyPct: (j['accuracy_pct'] as num?)?.toDouble(),
        reviewTotal: (j['review_total'] as num?)?.toInt() ?? 0,
        reviewCorrect: (j['review_correct'] as num?)?.toInt() ?? 0,
        retentionPct: (j['retention_pct'] as num?)?.toDouble(),
      );
}

/// What the add/edit forms produce. Saving it is the caller's job
/// (`Repository.addWords` / `updateWord`).
class WordDraft {
  const WordDraft({
    required this.term,
    this.reading,
    this.meaning,
    this.meaningMn,
    this.example,
    this.exampleLater,
  });

  final String term;
  final String? reading;
  final String? meaning;
  final String? meaningMn;

  /// A sentence still being looked up when the word was saved
  /// (ExampleController.take): the repository writes it onto the word when
  /// it lands, if the word has none by then. Never queued offline.
  final Future<WordExample?>? exampleLater;

  /// Null leaves the word's sentence as it is; an empty one clears it. Kept
  /// apart from "empty" so a save never names the 0031 columns unless it has
  /// to — a database without that migration still takes every other edit.
  final WordExample? example;
}

/// A word's example sentence and its translations (`words.example_*`, 0031).
/// Any part may be empty; a sentence with no translation is still worth
/// showing.
class WordExample {
  const WordExample({this.ja = '', this.en = '', this.mn = '', this.furigana});

  final String ja;
  final String en;
  final String mn;

  /// Reading markup for [ja] (0032), from Tatoeba; null for a sentence the
  /// user wrote, and dropped once the sentence no longer matches it.
  final String? furigana;

  bool get isEmpty => ja.isEmpty && en.isEmpty && mn.isEmpty;

  /// Null when the row has no sentence (or predates 0031).
  static WordExample? fromRow(Map<String, dynamic> j) {
    final ja = (j['example_ja'] as String? ?? '').trim();
    if (ja.isEmpty) return null;
    return WordExample(
      ja: ja,
      en: (j['example_en'] as String? ?? '').trim(),
      mn: (j['example_mn'] as String? ?? '').trim(),
      furigana: furiganaFor(ja, j['example_furigana'] as String?),
    );
  }

  /// The row values, empty parts as null.
  Map<String, String?> toRow() => {
        'example_ja': ja.isEmpty ? null : ja,
        'example_en': en.isEmpty ? null : en,
        'example_mn': mn.isEmpty ? null : mn,
        'example_furigana': furiganaFor(ja, furigana),
      };
}
