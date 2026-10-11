import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/confirm_dialog.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';

// Several words at once — the last batch, or a selection — deleted or moved
// to another deck, each with an undo on the snackbar. A capture pushed into
// the wrong deck is the case this exists for: moving it is usually what's
// wanted, deleting it the fallback.

/// How long an undo stays on offer.
const _undoFor = Duration(seconds: 6);

/// Asks, deletes, and offers to undo. Returns true when the words went.
Future<bool> deleteWordsWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
  required List<String> ids,
}) async {
  if (ids.isEmpty) return false;
  final ok = await askConfirm(
    context,
    title: T.deleteWordsTitle(ids.length),
    body: T.deleteWordsBody,
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  final repo = ref.read(repositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await repo.deleteWords(ids);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text(T.wordsActionFailed)));
    return false;
  }
  container.refreshLibrary(deckId: deckId);
  _offerUndo(messenger, T.wordsDeleted(ids.length), () async {
    await repo.restoreWords(ids);
    container.refreshLibrary(deckId: deckId);
  });
  return true;
}

/// Picks a deck, moves the words there, and offers to move them back.
/// Returns true when they moved.
Future<bool> moveWordsWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required String fromDeckId,
  required List<String> ids,
}) async {
  if (ids.isEmpty) return false;
  final decks = (ref.read(decksProvider).value ?? const <Deck>[]).where((d) => d.id != fromDeckId).toList();
  final target = await _pickDeck(context, decks);
  if (target == null || !context.mounted) return false;
  final repo = ref.read(repositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  void refresh() {
    container.refreshLibrary(deckId: fromDeckId);
    container.refreshLibrary(deckId: target.id);
  }

  try {
    await repo.moveWords(ids, target.id);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text(T.wordsActionFailed)));
    return false;
  }
  refresh();
  _offerUndo(messenger, T.wordsMoved(ids.length, target.name), () async {
    await repo.moveWords(ids, fromDeckId);
    refresh();
  });
  return true;
}

/// A snackbar whose action runs [undo], then says whether it worked.
void _offerUndo(ScaffoldMessengerState messenger, String message, Future<void> Function() undo) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: _undoFor,
        // Flutter keeps a snackbar with an action up until it's tapped
        // (persist defaults to true then); an undo offer should time out.
        persist: false,
        action: SnackBarAction(
          label: T.undo,
          onPressed: () async {
            try {
              await undo();
              messenger.showSnackBar(const SnackBar(content: Text(T.wordsUndone)));
            } catch (_) {
              messenger.showSnackBar(const SnackBar(content: Text(T.wordsActionFailed)));
            }
          },
        ),
      ),
    );
}

Future<Deck?> _pickDeck(BuildContext context, List<Deck> decks) {
  return showModalBottomSheet<Deck>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(T.pickTargetDeck, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in decks)
                  ListTile(
                    leading: Icon(Icons.style_outlined, color: ctx.hk.inkSoft),
                    title: Text(d.name),
                    onTap: () => Navigator.of(ctx).pop(d),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
