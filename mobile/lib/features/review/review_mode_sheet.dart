import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_router.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../../models/queue_card.dart';
import '../battle/hero.dart';
import '../battle/rules.dart' show minWordsForBattle;
import '../battle/sprite_view.dart';

/// Words you keep failing in the scope, for the leech link. Zero (no link)
/// if it can't be fetched — the link is a nudge, not a feature to fail on.
final _leechCountProvider = FutureProvider.family<int, String?>((ref, deckId) async {
  try {
    return (await ref.watch(repositoryProvider).leechCards(deckId: deckId)).length;
  } catch (_) {
    return 0;
  }
});

final _scopedDueProvider = FutureProvider.family<DueSummary, String?>(
  (ref, deckId) => ref.watch(repositoryProvider).dueSummary(deckId: deckId),
);

/// Mode picker, the mobile take on web/src/app/decks/review/_components/
/// ReviewModePicker.tsx: the due count for the chosen scope up front (split
/// into reviews and new, under the daily caps), deck scope chips, then three
/// modes — Monster Hunt (every question kind), classic cards, kanji writing —
/// and a link to leech rescue when there are leeches. Returns the route to
/// push, or null if dismissed.
Future<String?> showReviewModeSheet(BuildContext context, {String? deckId}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReviewModeSheet(initialDeckId: deckId),
  );
}

class _ReviewModeSheet extends ConsumerStatefulWidget {
  const _ReviewModeSheet({this.initialDeckId});
  final String? initialDeckId;

  @override
  ConsumerState<_ReviewModeSheet> createState() => _ReviewModeSheetState();
}

class _ReviewModeSheetState extends ConsumerState<_ReviewModeSheet> {
  late String? _deckId = widget.initialDeckId;

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).value ?? const <Deck>[];
    final due = ref.watch(_scopedDueProvider(_deckId));
    final hero = ref.watch(heroProvider);
    // Monster Hunt needs four of your own words to build four options.
    final wordCount = ref.watch(allWordsProvider).value?.length;
    final huntLocked = wordCount != null && wordCount < minWordsForBattle;
    final deckName = decks.where((d) => d.id == _deckId).firstOrNull?.name;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(T.practiceKicker.toUpperCase(),
              style: TextStyle(
                  fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700, color: context.hk.sealText)),
          const SizedBox(height: 6),
          due.when(
            loading: () => const SizedBox(height: 52, child: LinearProgressIndicator()),
            error: (e, _) => Text(T.loadFailed, style: theme.textTheme.titleLarge),
            data: (d) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.dueNow > 0 ? T.practiceDueHeadline(d.dueNow) : T.practiceNothingDue,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (d.dueNow > 0)
                  Text(
                    T.practiceDueBreakdown(
                      d.dueNow - (d.newDue < d.newRemaining ? d.newDue : d.newRemaining),
                      d.newDue < d.newRemaining ? d.newDue : d.newRemaining,
                    ),
                    style: TextStyle(color: context.hk.inkSoft),
                  ),
                if (d.heldBack > 0)
                  Text(T.dueHeldBack(d.heldBack),
                      style: TextStyle(fontSize: 12, color: context.hk.inkMute)),
              ],
            ),
          ),
          if (decks.length > 1) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip(T.practiceScopeAll, null),
                  for (final d in decks) _chip(d.name, d.id),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Mode(
            leading: SizedBox.square(
              dimension: 56,
              child: SpriteView(slug: hero, size: 56),
            ),
            title: T.battleModeTitle,
            subtitle: T.huntDescMobile,
            note: huntLocked ? T.battleLocked(minWordsForBattle) : null,
            onTap: huntLocked
                ? null
                : () => Navigator.of(context).pop(Routes.hunt(deckId: _deckId)),
          ),
          _Mode(
            leading: Icon(Icons.style_outlined, color: context.hk.sealText, size: 30),
            title: T.classicModeTitle,
            subtitle: T.classicModeDesc,
            onTap: () => Navigator.of(context)
                .pop(Routes.review(deckId: _deckId, deckName: deckName)),
          ),
          _Mode(
            leading: Icon(Icons.draw_outlined, color: context.hk.sealText, size: 30),
            title: T.writingTitle,
            subtitle: T.writingDesc,
            onTap: () => Navigator.of(context).pop(
              Uri(path: Routes.writing, queryParameters: {'deck': ?_deckId}).toString(),
            ),
          ),
          // Leeches aren't a mode: most days there are none, and a permanent
          // row for an empty list is clutter. The link appears only when
          // there's something to rescue.
          ref.watch(_leechCountProvider(_deckId)).maybeWhen(
                data: (n) => n == 0
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.healing_outlined, size: 18),
                          label: Text(T.leechLink(n)),
                          onPressed: () => Navigator.of(context).pop(
                            Uri(path: Routes.leech, queryParameters: {'deck': ?_deckId}).toString(),
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? id) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _deckId == id,
          onSelected: (_) => setState(() => _deckId = id),
        ),
      );
}

class _Mode extends StatelessWidget {
  const _Mode({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.note,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        enabled: onTap != null,
        leading: leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(note == null ? subtitle : '$subtitle\n$note',
            style: const TextStyle(fontSize: 12)),
        isThreeLine: note != null,
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
