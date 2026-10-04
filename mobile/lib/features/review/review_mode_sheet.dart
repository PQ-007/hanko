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
import '../battle/sprite_view.dart';

final _scopedDueProvider = FutureProvider.family<DueSummary, String?>(
  (ref, deckId) => ref.watch(repositoryProvider).dueSummary(deckId: deckId),
);

/// Mode picker, the mobile take on web/src/app/decks/review/_components/
/// ReviewModePicker.tsx: the due count for the chosen scope up front (split
/// into reviews and new, under the daily caps), deck scope chips, then the
/// modes. Returns the route to push, or null if dismissed.
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
    final deckName = decks.where((d) => d.id == _deckId).firstOrNull?.name;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(T.practiceKicker.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700, color: HankoColors.seal)),
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
            subtitle: T.battleModeDesc,
            note: T.nextStage,
          ),
          _Mode(
            leading: const Icon(Icons.style_outlined, color: HankoColors.seal, size: 30),
            title: T.classicModeTitle,
            subtitle: T.classicModeDesc,
            onTap: () => Navigator.of(context)
                .pop(Routes.review(deckId: _deckId, deckName: deckName)),
          ),
          _Mode(
            leading: const Icon(Icons.bolt_outlined, color: HankoColors.seal, size: 30),
            title: T.speedRoundTitle,
            subtitle: T.speedRoundDesc,
            onTap: () => Navigator.of(context).pop(
              Uri(path: Routes.speed, queryParameters: {'deck': ?_deckId}).toString(),
            ),
          ),
          _Mode(
            leading: const Icon(Icons.healing_outlined, color: HankoColors.seal, size: 30),
            title: T.leechTitle,
            subtitle: T.leechDesc,
            onTap: () => Navigator.of(context).pop(
              Uri(path: Routes.leech, queryParameters: {'deck': ?_deckId}).toString(),
            ),
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
