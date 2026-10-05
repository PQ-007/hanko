import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../models/library.dart';
import '../decks/word_actions.dart';
import 'export_text.dart';
import 'folder_picker.dart';
import 'folder_tree.dart';

Future<void> renameDeck(BuildContext context, WidgetRef ref, Deck deck) async {
  final name = await promptName(
    context,
    title: T.rename,
    action: T.save,
    initial: deck.name,
  );
  // An unchanged name isn't an edit — skip the round trip rather than bumping
  // updated_at and making every other client re-pull the row.
  if (name == null || name == deck.name) return;
  try {
    await ref.read(repositoryProvider).renameDeck(deck.id, name);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> moveDeck(BuildContext context, WidgetRef ref, Deck deck) async {
  final folders = await ref.read(foldersProvider.future);
  if (!context.mounted) return;
  final choice = await pickFolder(
    context,
    folders: folders,
    currentId: deck.folderId,
  );
  if (choice == null) return;
  final target = switch (choice) {
    PickedRoot() => null,
    PickedFolder(:final id) => id,
  };
  if (target == deck.folderId) return;
  try {
    await ref.read(repositoryProvider).moveDeck(deck.id, target);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

/// Returns true if deleted, so a deck page can pop itself.
Future<bool> deleteDeck(BuildContext context, WidgetRef ref, Deck deck) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(T.deleteDeckConfirm(deck.name)),
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
  if (ok != true) return false;
  try {
    await ref.read(repositoryProvider).deleteDeck(deck.id);
    ref.refreshLibrary();
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$e');
    return false;
  }
}

/// Builds the deck's Anki-importable .txt on the phone and hands it to the
/// system share sheet — no server involved.
Future<void> exportDeckTxt(
  BuildContext context,
  WidgetRef ref,
  Deck deck,
) async {
  try {
    final words = await ref.read(deckWordsProvider(deck.id).future);
    if (words.isEmpty) {
      if (context.mounted) toast(context, T.noWords);
      return;
    }
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/${sanitizeFilename(deck.name)}.txt');
    await out.writeAsString(buildDeckTxt(deck.name, words), flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(out.path)], subject: deck.name),
    );
  } catch (e) {
    if (context.mounted) toast(context, '${T.exportFailed}: $e');
  }
}

Future<void> createFolder(
  BuildContext context,
  WidgetRef ref, {
  Folder? parent,
}) async {
  final name = await promptName(
    context,
    title: parent == null ? T.newFolderTitle : T.newFolderInside,
    action: T.create,
  );
  if (name == null) return;
  try {
    await ref.read(repositoryProvider).createFolder(name, parentId: parent?.id);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> createDeck(
  BuildContext context,
  WidgetRef ref, {
  Folder? folder,
}) async {
  final name = await promptName(context, title: T.newDeck, action: T.create);
  if (name == null) return;
  try {
    await ref.read(repositoryProvider).createDeck(name, folderId: folder?.id);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> renameFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final name = await promptName(
    context,
    title: T.rename,
    action: T.save,
    initial: folder.name,
  );
  if (name == null || name == folder.name) return;
  try {
    await ref.read(repositoryProvider).renameFolder(folder.id, name);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> moveFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final folders = await ref.read(foldersProvider.future);
  if (!context.mounted) return;
  final choice = await pickFolder(
    context,
    folders: folders,
    currentId: folder.parentId,
    exclude: subtreeIds(folders, folder.id),
  );
  if (choice == null) return;
  final target = switch (choice) {
    PickedRoot() => null,
    PickedFolder(:final id) => id,
  };
  if (target == folder.parentId) return;
  try {
    await ref.read(repositoryProvider).moveFolder(folder.id, target);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> deleteFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(T.deleteFolderConfirm(folder.name)),
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
    await ref.read(repositoryProvider).deleteFolder(folder.id);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

/// Creates a deck, optionally inside an existing folder or a brand-new one,
/// from one dialog — the camera capture saves a page of words into it without
/// a detour through the Library. Returns the new deck's id, or null if
/// cancelled or it failed (the failure is shown).
Future<String?> createDeckInFolder(
  BuildContext context,
  WidgetRef ref, {
  String initialName = '',
}) async {
  final folders = await ref.read(foldersProvider.future);
  if (!context.mounted) return null;
  final result = await showDialog<_NewDeck>(
    context: context,
    builder: (_) => _NewDeckDialog(folders: folders, initialName: initialName),
  );
  if (result == null) return null;
  final repo = ref.read(repositoryProvider);
  try {
    final folderId = result.newFolder != null
        ? await repo.createFolder(result.newFolder!)
        : result.folderId;
    final id = await repo.createDeck(result.name, folderId: folderId);
    ref.refreshLibrary();
    return id;
  } catch (e) {
    if (context.mounted) toast(context, '$e');
    return null;
  }
}

typedef _NewDeck = ({String name, String? folderId, String? newFolder});

class _NewDeckDialog extends StatefulWidget {
  const _NewDeckDialog({required this.folders, required this.initialName});
  final List<Folder> folders;
  final String initialName;

  @override
  State<_NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends State<_NewDeckDialog> {
  static const _newFolder = '__new__';
  late final _name = TextEditingController(text: widget.initialName);
  final _folderName = TextEditingController();
  String? _folder;

  @override
  void dispose() {
    _name.dispose();
    _folderName.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final folderName = _folderName.text.trim();
    if (name.isEmpty || (_folder == _newFolder && folderName.isEmpty)) return;
    Navigator.of(context).pop<_NewDeck>((
      name: name,
      folderId: _folder == _newFolder ? null : _folder,
      newFolder: _folder == _newFolder ? folderName : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final flat = flattenTree(buildLibraryTree(widget.folders, const []).roots);
    return AlertDialog(
      title: const Text(T.captureNewDeckTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: T.newDeck),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _folder,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: T.captureFolderLabel,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text(T.noFolderOption),
                ),
                for (final (f, depth) in flat)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text(
                      '${'  ' * depth}${f.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(
                  value: _newFolder,
                  child: Text(T.captureNewFolderOption),
                ),
              ],
              onChanged: (v) => setState(() => _folder = v),
            ),
            if (_folder == _newFolder) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _folderName,
                autofocus: true,
                decoration: const InputDecoration(labelText: T.newFolder),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(T.cancel),
        ),
        FilledButton(onPressed: _submit, child: const Text(T.create)),
      ],
    );
  }
}
