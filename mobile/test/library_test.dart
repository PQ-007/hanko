import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/folder_tree.dart';
import 'package:mobile/models/library.dart';

Folder folder(String id, {String? parent}) =>
    Folder(id: id, name: id, parentId: parent, createdAt: DateTime(2026));

Deck deck(String id, {String? folder}) => Deck(id: id, name: id, folderId: folder);

void main() {
  group('gradeFor matches web/src/lib/srs.ts boundaries', () {
    // Same cases as the web's srs.test.ts gradeFor block.
    test('new', () => expect(gradeFor(repetitions: 0, intervalDays: 0), Grade.newWord));
    test('1 → F', () => expect(gradeFor(repetitions: 1, intervalDays: 1), Grade.f));
    test('6 → D', () => expect(gradeFor(repetitions: 2, intervalDays: 6), Grade.d));
    test('21 → C', () => expect(gradeFor(repetitions: 3, intervalDays: 21), Grade.c));
    test('60 → B', () => expect(gradeFor(repetitions: 5, intervalDays: 60), Grade.b));
    test('61 → A', () => expect(gradeFor(repetitions: 10, intervalDays: 61), Grade.a));
    test('only A and B count as mastered', () {
      expect(Grade.values.where((g) => g.mastered), [Grade.b, Grade.a]);
    });
  });

  group('buildLibraryTree', () {
    test('nests folders and files decks under them', () {
      final tree = buildLibraryTree(
        [folder('a'), folder('b', parent: 'a')],
        [deck('d1', folder: 'b'), deck('d2')],
      );
      expect(tree.roots.map((n) => n.folder.id), ['a']);
      expect(tree.roots.single.children.single.folder.id, 'b');
      expect(tree.roots.single.children.single.decks.single.id, 'd1');
      expect(tree.roots.single.totalDecks, 1);
      expect(tree.unfiled.map((d) => d.id), ['d2']);
    });

    test('a parent that is gone (tombstoned) puts the child at root', () {
      final tree = buildLibraryTree([folder('child', parent: 'deleted')], const []);
      expect(tree.roots.single.folder.id, 'child');
    });

    test('a deck whose folder is gone is unfiled, like the web sidebar', () {
      final tree = buildLibraryTree(const [], [deck('d', folder: 'deleted')]);
      expect(tree.unfiled.single.id, 'd');
    });

    test('a cycle degrades to root instead of vanishing', () {
      // The database trigger forbids this; the client still must not lose
      // folders if a bad row ever gets through.
      final tree = buildLibraryTree(
        [folder('x', parent: 'y'), folder('y', parent: 'x')],
        const [],
      );
      final all = flattenTree(tree.roots).map((e) => e.$1.id).toSet();
      expect(all, {'x', 'y'});
    });
  });

  test('subtreeIds covers the folder and everything beneath it', () {
    final folders = [
      folder('a'),
      folder('b', parent: 'a'),
      folder('c', parent: 'b'),
      folder('z'),
    ];
    expect(subtreeIds(folders, 'a'), {'a', 'b', 'c'});
    expect(subtreeIds(folders, 'z'), {'z'});
  });
}
