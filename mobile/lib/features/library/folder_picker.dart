import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import 'folder_tree.dart';

/// What the picker returned: a folder id, or root.
sealed class FolderChoice {
  const FolderChoice();
}

class PickedRoot extends FolderChoice {
  const PickedRoot();
}

class PickedFolder extends FolderChoice {
  const PickedFolder(this.id);
  final String id;
}

/// Bottom sheet listing the folder tree, indented. [exclude] folders are
/// shown disabled (a folder can't move into itself or its own subtree).
Future<FolderChoice?> pickFolder(
  BuildContext context, {
  required List<Folder> folders,
  String? currentId,
  Set<String> exclude = const {},
}) {
  final flat = flattenTree(buildLibraryTree(folders, const []).roots);
  return showModalBottomSheet<FolderChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(T.moveTo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text(T.moveToRoot),
            selected: currentId == null,
            onTap: () => Navigator.of(ctx).pop(const PickedRoot()),
          ),
          for (final (folder, depth) in flat)
            ListTile(
              contentPadding: EdgeInsets.only(left: 16.0 + depth * 20, right: 16),
              leading: Icon(
                Icons.folder_outlined,
                color: exclude.contains(folder.id) ? context.hk.line : HankoColors.seal,
              ),
              title: Text(folder.name),
              enabled: !exclude.contains(folder.id),
              selected: folder.id == currentId,
              onTap: () => Navigator.of(ctx).pop(PickedFolder(folder.id)),
            ),
        ],
      ),
    ),
  );
}
