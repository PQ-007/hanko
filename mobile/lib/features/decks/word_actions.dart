import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/speech.dart';
import '../../core/strings.dart';
import '../../models/library.dart';

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Adds one word, asking first if the term is already in the deck — the same
/// "add anyway?" the web shows. Returns true when the word was saved.
///
/// Asks the server rather than a loaded list (like QuickAddWordModal.tsx), so
/// it works the same from a deck page, the quick-add sheet or anywhere else.
Future<bool> addWordChecked(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
  required WordDraft draft,
}) async {
  final repo = ref.read(repositoryProvider);
  try {
    final existing = await repo.existingTerms(deckId, [draft.term]);
    if (existing.isNotEmpty) {
      if (!context.mounted) return false;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(T.duplicateWord),
          content: Text(T.duplicateWordConfirm(draft.term)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(T.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(T.addAnyway),
            ),
          ],
        ),
      );
      if (ok != true) return false;
    }
    await repo.addWords(deckId, [draft]);
    ref.refreshLibrary(deckId: deckId);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '${T.quickAddSaveFailed} $e');
    return false;
  }
}

/// Plays a word's pronunciation: its recorded clip if it has one (captured by
/// the extension or the web), otherwise the phone's own Japanese voice.
Future<void> playWord(BuildContext context, WidgetRef ref, Word word) async {
  final path = word.audioPath;
  if (path != null && path.isNotEmpty) {
    await ref.read(audioProvider).play(word.id, path);
    return;
  }
  await speakWord(context, ref, reading: word.reading, term: word.term);
}

/// Speaks the reading (or the term, for kana words) with on-device TTS.
Future<void> speakWord(
  BuildContext context,
  WidgetRef ref, {
  String? reading,
  required String term,
}) async {
  final text = (reading != null && reading.isNotEmpty) ? reading : term;
  final ok = await ref.read(speechProvider).speakJapanese(text);
  if (!ok && context.mounted) toast(context, T.noJapaneseVoice);
}

Future<void> confirmDeleteWord(BuildContext context, WidgetRef ref, Word word) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('“${word.term}” — ${T.removeWord}?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(T.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(T.delete),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(repositoryProvider).deleteWord(word.id);
    ref.refreshLibrary(deckId: word.deckId);
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

/// Shared name prompt for creating/renaming decks and folders.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, action: action, initial: initial),
  );
  return (name == null || name.isEmpty) ? null : name;
}

/// Owns its controller, so it's disposed with the dialog rather than while the
/// closing animation is still drawing the field.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.action, required this.initial});
  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: T.name),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(T.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
