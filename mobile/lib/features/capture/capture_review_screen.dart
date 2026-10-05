import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/dictionary.dart';
import '../../core/offline_words.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../battle/fight_scene.dart';
import '../decks/word_actions.dart';
import '../decks/word_editor.dart';
import '../library/deck_actions.dart';
import '../shell/quick_add_sheet.dart';
import 'capture_lookup.dart';

/// Camera capture, step two: every chosen word looked up and filled in, ready
/// to edit, deselect, and save into one deck in a single batch.
///
/// Words already in the chosen deck are deselected and badged, from one query
/// for the whole list. New words get their `state='new'` card from the
/// database trigger, exactly like words from the extension or the web.
class CaptureReviewScreen extends ConsumerStatefulWidget {
  const CaptureReviewScreen({super.key, required this.terms});
  final List<String> terms;

  @override
  ConsumerState<CaptureReviewScreen> createState() =>
      _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends ConsumerState<CaptureReviewScreen> {
  List<CaptureItem>? _items;
  int _done = 0;
  String? _deckId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deckId = prefs.getString(quickAddDeckKey);
    } catch (_) {}
    final items = await resolveCapture(
      widget.terms,
      ref.read(dictionaryProvider),
      onProgress: (done, _) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (!mounted) return;
    setState(() => _items = items);
    final decks = await ref.read(decksProvider.future);
    if (mounted && decks.isNotEmpty) {
      _pickDeck(_resolveDeck(decks.map((d) => d.id)));
    }
  }

  String _resolveDeck(Iterable<String> ids) =>
      ids.contains(_deckId) ? _deckId! : ids.first;

  Future<void> _pickDeck(String id) async {
    setState(() => _deckId = id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(quickAddDeckKey, id);
    } catch (_) {}
    await _checkDuplicates(id);
  }

  /// Deselects what the deck already has. Offline, nothing is known to be a
  /// duplicate, so nothing is deselected.
  Future<void> _checkDuplicates(String deckId) async {
    final items = _items;
    if (items == null) return;
    Set<String> existing;
    try {
      existing = await ref
          .read(repositoryProvider)
          .existingTerms(deckId, items.map((i) => i.draft.term));
    } catch (_) {
      existing = {};
    }
    if (!mounted || deckId != _deckId) return;
    setState(() {
      for (final i in items) {
        i.inDeck = existing.contains(i.draft.term);
        i.selected = !i.inDeck;
      }
    });
  }

  /// A new deck (optionally in a new folder) for this page of words, picked
  /// as the target straight away.
  Future<void> _newDeck() async {
    final id = await createDeckInFolder(
      context,
      ref,
      initialName: T.captureDeckName(DateTime.now()),
    );
    if (id == null || !mounted) return;
    await ref.read(decksProvider.future);
    if (mounted) await _pickDeck(id);
  }

  Future<void> _edit(CaptureItem item) async {
    final draft = await showWordEditor(context, draft: item.draft);
    if (draft == null || !mounted) return;
    setState(() => item.draft = draft);
    final deckId = _deckId;
    if (deckId == null) return;
    try {
      final existing = await ref.read(repositoryProvider).existingTerms(
        deckId,
        [draft.term],
      );
      if (mounted) setState(() => item.inDeck = existing.isNotEmpty);
    } catch (_) {}
  }

  Future<void> _save() async {
    final deckId = _deckId;
    final chosen = [
      for (final i in _items ?? const <CaptureItem>[])
        if (i.selected) i.draft,
    ];
    if (deckId == null || chosen.isEmpty) return;
    setState(() => _saving = true);
    final outcome = await ref.read(wordOutboxProvider).save(deckId, chosen);
    if (!mounted) return;
    ref.refreshLibrary(deckId: deckId);
    toast(
      context,
      outcome == SaveOutcome.saved
          ? T.captureSaved(chosen.length)
          : T.captureQueued(chosen.length),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final decks = ref.watch(decksProvider).value ?? const [];
    final selected = items?.where((i) => i.selected).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text(T.captureReviewTitle)),
      body: items == null
          ? LoadingScene(
              label: '${T.captureLookingUp} $_done/${widget.terms.length}',
            )
          : decks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(T.quickAddNoDecks, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _newDeck,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text(T.captureNewDeck),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_deckId),
                        initialValue: _resolveDeck(decks.map((d) => d.id)),
                        decoration: const InputDecoration(
                          labelText: T.quickAddDeckLabel,
                        ),
                        items: [
                          for (final d in decks)
                            DropdownMenuItem(value: d.id, child: Text(d.name)),
                        ],
                        onChanged: (v) {
                          if (v != null) _pickDeck(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: T.captureNewDeck,
                      onPressed: _newDeck,
                      icon: const Icon(Icons.create_new_folder_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final item in items) ...[
                  _ItemTile(
                    item: item,
                    onToggle: () =>
                        setState(() => item.selected = !item.selected),
                    onEdit: () => _edit(item),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
      bottomNavigationBar: items == null || decks.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: selected == 0 || _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(T.captureSave(selected)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.onToggle,
    required this.onEdit,
  });
  final CaptureItem item;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final d = item.draft;
    final muted = TextStyle(fontSize: 12, color: context.hk.inkMute);
    final meaning = [
      d.meaningMn,
      d.meaning,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              Checkbox(value: item.selected, onChanged: (_) => onToggle()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(
                          d.term,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (d.reading != null)
                          Text(
                            d.reading!,
                            style: TextStyle(color: context.hk.inkMute),
                          ),
                      ],
                    ),
                    if (meaning.isNotEmpty)
                      Text(
                        meaning,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (!item.found) Text(T.captureNoLookup, style: muted),
                    if (item.inDeck)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.hk.sealTint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            T.captureAlreadyInDeck,
                            style: TextStyle(
                              fontSize: 11,
                              color: HankoColors.seal,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: T.editWord,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
