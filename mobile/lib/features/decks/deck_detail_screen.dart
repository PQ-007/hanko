import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repository.dart';
import '../review/review_screen.dart';
import 'word_editor.dart';

final _wordsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, deckId) => ref.watch(repositoryProvider).words(deckId),
);

/// A deck's words, with manual add/edit/delete.
///
/// Capture is the extension's job — this exists for the cases where you're away
/// from a desktop and want a word in now, and for fixing a meaning you got
/// wrong. It writes plain `words` rows exactly like the extension does, so the
/// card is created by the same server-side trigger.
class DeckDetailScreen extends ConsumerWidget {
  const DeckDetailScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showWordEditor(context);
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider).addWord(
            deckId: deckId,
            term: draft.term,
            reading: draft.reading,
            meaning: draft.meaning,
            meaningMn: draft.meaningMn,
          );
      ref.invalidate(_wordsProvider(deckId));
    } catch (e) {
      if (context.mounted) _toast(context, 'Нэмж чадсангүй: $e');
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> word,
  ) async {
    final draft = await showWordEditor(context, existing: word);
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider).updateWord(
            wordId: word['id'] as String,
            term: draft.term,
            reading: draft.reading,
            meaning: draft.meaning,
            meaningMn: draft.meaningMn,
          );
      ref.invalidate(_wordsProvider(deckId));
    } catch (e) {
      if (context.mounted) _toast(context, 'Хадгалж чадсангүй: $e');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> word,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"${word['term']}" устгах уу?'),
        content: const Text('Энэ үгийн давталтын түүх ч мөн алга болно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Болих'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deleteWord(word['id'] as String);
      ref.invalidate(_wordsProvider(deckId));
    } catch (e) {
      if (context.mounted) _toast(context, 'Устгаж чадсангүй: $e');
    }
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(_wordsProvider(deckId));

    return Scaffold(
      appBar: AppBar(
        title: Text(deckName),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Энэ багцыг давтах',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ReviewScreen(deckId: deckId, deckName: deckName),
                ),
              );
              ref.invalidate(_wordsProvider(deckId));
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add),
      ),
      body: words.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Уншиж чадсангүй:\n$e'),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Энэ багцад үг алга.\nДоорх + товчоор нэмнэ үү.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_wordsProvider(deckId)),
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final w = rows[i];
                final reading = w['reading'] as String?;
                final mn = w['meaning_mn'] as String?;
                final en = w['meaning'] as String?;
                final subtitle = [
                  if (reading != null && reading.isNotEmpty) reading,
                  if (mn != null && mn.isNotEmpty) mn,
                  if (en != null && en.isNotEmpty) en,
                ].join(' · ');

                return ListTile(
                  title: Text(w['term'] as String? ?? '—'),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onTap: () => _edit(context, ref, w),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _delete(context, ref, w),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
