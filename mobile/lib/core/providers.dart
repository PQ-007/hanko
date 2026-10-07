import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/library.dart';
import '../models/queue_card.dart';
import 'repository.dart';

// Shared by every tab. These used to be file-private to individual screens,
// which meant the Home tab and the Library could each hold a different idea of
// what's due. One copy, invalidated from one place (below), keeps them agreeing.

final foldersProvider = FutureProvider<List<Folder>>(
  (ref) => ref.watch(repositoryProvider).folders(),
);

final decksProvider = FutureProvider<List<Deck>>(
  (ref) => ref.watch(repositoryProvider).decks(),
);

/// Every live word. Per-deck counts, the stats charts and the word spotlight
/// all derive from this one read, as on the web dashboard.
final allWordsProvider = FutureProvider<List<Word>>(
  (ref) => ref.watch(repositoryProvider).allWords(),
);

final deckWordsProvider = FutureProvider.family<List<Word>, String>(
  (ref, deckId) => ref.watch(repositoryProvider).words(deckId),
);

final dueSummaryProvider = FutureProvider<DueSummary>(
  (ref) => ref.watch(repositoryProvider).dueSummary(),
);

final activityProvider = FutureProvider<Map<DateTime, int>>(
  (ref) => ref.watch(repositoryProvider).reviewActivity(),
);

final freezesProvider = FutureProvider<int>(
  (ref) => ref.watch(repositoryProvider).streakFreezes(),
);

/// The scheduler's today. Null if 0019 isn't applied; callers then fall back
/// to the device date.
final srsTodayProvider = FutureProvider<DateTime?>(
  (ref) => ref.watch(repositoryProvider).currentSrsDay(),
);

final reviewStatsProvider = FutureProvider<ReviewStats?>(
  (ref) => ref.watch(repositoryProvider).reviewStats(),
);

/// Word count per deck id, derived from [allWordsProvider].
final deckCountsProvider = Provider<AsyncValue<Map<String, int>>>((ref) {
  return ref.watch(allWordsProvider).whenData((words) {
    final counts = <String, int>{};
    for (final w in words) {
      counts[w.deckId] = (counts[w.deckId] ?? 0) + 1;
    }
    return counts;
  });
});

extension Refresh on WidgetRef {
  /// After anything that changes folders, decks or words.
  void refreshLibrary({String? deckId}) {
    invalidate(foldersProvider);
    invalidate(decksProvider);
    invalidate(allWordsProvider);
    invalidate(dueSummaryProvider);
    if (deckId != null) invalidate(deckWordsProvider(deckId));
  }

  /// After a review session: what's due, the streak and the stats all move.
  void refreshAfterReview() {
    invalidate(dueSummaryProvider);
    invalidate(activityProvider);
    invalidate(allWordsProvider);
    invalidate(reviewStatsProvider);
    invalidate(srsTodayProvider);
    invalidate(deckWordsProvider);
  }

  void refreshAll() {
    refreshLibrary();
    refreshAfterReview();
    invalidate(freezesProvider);
  }
}
