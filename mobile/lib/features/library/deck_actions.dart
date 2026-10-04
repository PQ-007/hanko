import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/web_api.dart';
import '../../models/library.dart';
import '../decks/word_actions.dart';
import 'folder_picker.dart';
import 'folder_tree.dart';

Future<void> renameDeck(BuildContext context, WidgetRef ref, Deck deck) async {
  final name = await promptName(context, title: T.rename, action: T.save, initial: deck.name);
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
  final choice = await pickFolder(context, folders: folders, currentId: deck.folderId);
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
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text(T.cancel)),
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

/// Builds the export on the server (same routes the web uses, Bearer-authed)
/// and hands the file to the system share sheet.
Future<void> exportDeck(BuildContext context, WidgetRef ref, Deck deck, String format) async {
  final api = ref.read(webApiProvider);
  if (!api.available) {
    toast(context, T.lookupUnavailable);
    return;
  }
  toast(context, T.building);
  try {
    final file = await api.exportDeck(deck.id, format);
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/${file.filename}');
    await out.writeAsBytes(file.bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(out.path)], subject: deck.name));
  } catch (e) {
    if (context.mounted) toast(context, '${T.exportFailed}: $e');
  }
}

Future<void> createFolder(BuildContext context, WidgetRef ref, {Folder? parent}) async {
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

Future<void> createDeck(BuildContext context, WidgetRef ref, {Folder? folder}) async {
  final name = await promptName(context, title: T.newDeck, action: T.create);
  if (name == null) return;
  try {
    await ref.read(repositoryProvider).createDeck(name, folderId: folder?.id);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> renameFolder(BuildContext context, WidgetRef ref, Folder folder) async {
  final name = await promptName(context, title: T.rename, action: T.save, initial: folder.name);
  if (name == null || name == folder.name) return;
  try {
    await ref.read(repositoryProvider).renameFolder(folder.id, name);
    ref.refreshLibrary();
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> moveFolder(BuildContext context, WidgetRef ref, Folder folder) async {
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

Future<void> deleteFolder(BuildContext context, WidgetRef ref, Folder folder) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(T.deleteFolderConfirm(folder.name)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text(T.cancel)),
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
