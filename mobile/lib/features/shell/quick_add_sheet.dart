import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_router.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../decks/word_actions.dart';
import '../decks/word_editor.dart';

/// Same key name as the web (QuickAddWordModal.tsx): per-device is the honest
/// scope for a convenience no other client reads.
const _deckKey = 'hanko.quickAdd.deck';

/// Add words without opening a deck first. Stays open after each add — the
/// reason to want this is a handful of words at once — and shows a running
/// count.
Future<void> showQuickAddSheet(BuildContext context, WidgetRef ref, {String? deckId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _QuickAdd(initialDeckId: deckId),
    ),
  );
}

class _QuickAdd extends ConsumerStatefulWidget {
  const _QuickAdd({this.initialDeckId});
  final String? initialDeckId;

  @override
  ConsumerState<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<_QuickAdd> {
  final _form = GlobalKey<WordFormState>();
  String? _deckId;
  int _added = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _deckId = widget.initialDeckId;
    if (_deckId == null) _restoreDeck();
  }

  Future<void> _restoreDeck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_deckKey);
      if (mounted && stored != null) setState(() => _deckId = stored);
    } catch (_) {}
  }

  Future<void> _pickDeck(String id) async {
    setState(() => _deckId = id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deckKey, id);
    } catch (_) {}
  }

  Future<void> _add(WordDraft draft, String deckId) async {
    setState(() => _busy = true);
    final saved = await addWordChecked(context, ref, deckId: deckId, draft: draft);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved) _added += 1;
    });
    if (saved) _form.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).value ?? const [];

    if (decks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(T.quickAddNoDecks),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go(Routes.library);
              },
              child: const Text(T.decks),
            ),
          ],
        ),
      );
    }

    // A remembered deck that's since been deleted falls back to the first.
    final deckId = decks.any((d) => d.id == _deckId) ? _deckId! : decks.first.id;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(T.quickAddTitle,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                if (_added > 0)
                  Text('✓ ${T.quickAddedCount(_added)}',
                      style: const TextStyle(
                          color: HankoColors.seal, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: DropdownButtonFormField<String>(
              initialValue: deckId,
              decoration: const InputDecoration(labelText: T.quickAddDeckLabel),
              items: [
                for (final d in decks) DropdownMenuItem(value: d.id, child: Text(d.name)),
              ],
              onChanged: (v) {
                if (v != null) _pickDeck(v);
              },
            ),
          ),
          WordForm(
            key: _form,
            busy: _busy,
            submitLabel: T.addWord,
            onSubmit: (draft) => _add(draft, deckId),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(T.quickAddDone),
            ),
          ),
        ],
      ),
    );
  }
}
