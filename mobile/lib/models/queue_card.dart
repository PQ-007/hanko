/// One row of the review queue: a card joined to the word it drills.
///
/// The shape is fixed by the `review_queue()` RPC
/// (supabase/migrations/0010_review_queue.sql). The server decides what is due —
/// day cutoff, per-day caps — so this app never re-derives it, and can't
/// disagree with the web app about what you owe today.
class QueueCard {
  const QueueCard({
    required this.cardId,
    required this.wordId,
    required this.deckId,
    required this.template,
    required this.state,
    required this.learningStep,
    required this.dueAt,
    required this.intervalDays,
    required this.repetitions,
    required this.easeFactor,
    required this.term,
    this.reading,
    this.meaning,
    this.meaningMn,
    this.audioPath,
  });

  final String cardId;
  final String wordId;
  final String deckId;
  final String template;

  /// new | learning | review | relearning
  final String state;
  final int learningStep;
  final DateTime dueAt;
  final int intervalDays;
  final int repetitions;
  final double easeFactor;

  final String term;
  final String? reading;
  final String? meaning;
  final String? meaningMn;
  final String? audioPath;

  /// Applies the scheduling fields returned by `review_card()` / `undo_review()`
  /// to the queue row already on screen, so a re-queued learning card keeps its
  /// word text without a second fetch.
  QueueCard copyWith({
    String? state,
    int? learningStep,
    int? intervalDays,
    int? repetitions,
    double? easeFactor,
  }) =>
      QueueCard(
        cardId: cardId,
        wordId: wordId,
        deckId: deckId,
        template: template,
        state: state ?? this.state,
        learningStep: learningStep ?? this.learningStep,
        dueAt: dueAt,
        intervalDays: intervalDays ?? this.intervalDays,
        repetitions: repetitions ?? this.repetitions,
        easeFactor: easeFactor ?? this.easeFactor,
        term: term,
        reading: reading,
        meaning: meaning,
        meaningMn: meaningMn,
        audioPath: audioPath,
      );

  factory QueueCard.fromJson(Map<String, dynamic> json) => QueueCard(
        cardId: json['card_id'] as String,
        wordId: json['word_id'] as String,
        deckId: json['deck_id'] as String,
        template: json['template'] as String,
        state: json['state'] as String,
        learningStep: (json['learning_step'] as num?)?.toInt() ?? 0,
        dueAt: DateTime.parse(json['due_at'] as String),
        intervalDays: (json['interval_days'] as num?)?.toInt() ?? 0,
        repetitions: (json['repetitions'] as num?)?.toInt() ?? 0,
        easeFactor: (json['ease_factor'] as num?)?.toDouble() ?? 2.5,
        term: json['term'] as String,
        reading: json['reading'] as String?,
        meaning: json['meaning'] as String?,
        meaningMn: json['meaning_mn'] as String?,
        audioPath: json['audio_path'] as String?,
      );
}

/// Result of the `due_summary()` RPC (0011): how much is due right now under
/// the same rules the review session uses. `dueNow` is what a session started
/// this second would actually serve — the number worth putting in front of a
/// user, and the one the "N cards due" notification will use.
class DueSummary {
  const DueSummary({
    required this.dueNow,
    required this.reviewDue,
    required this.newDue,
    required this.reviewRemaining,
    required this.newRemaining,
  });

  final int dueNow;
  final int reviewDue;
  final int newDue;
  final int reviewRemaining;
  final int newRemaining;

  /// Cards that are due but held back by today's cap.
  int get heldBack {
    final held = reviewDue + newDue - dueNow;
    return held > 0 ? held : 0;
  }

  factory DueSummary.fromJson(Map<String, dynamic> json) => DueSummary(
        dueNow: (json['due_now'] as num?)?.toInt() ?? 0,
        reviewDue: (json['review_due'] as num?)?.toInt() ?? 0,
        newDue: (json['new_due'] as num?)?.toInt() ?? 0,
        reviewRemaining: (json['review_remaining'] as num?)?.toInt() ?? 0,
        newRemaining: (json['new_remaining'] as num?)?.toInt() ?? 0,
      );
}
