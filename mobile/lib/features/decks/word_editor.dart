import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../../core/dictionary.dart';
import '../../models/library.dart';

export '../../models/library.dart' show WordDraft;

/// The add/edit form for a word, shown as a bottom sheet. Returns the entered
/// fields, or null if dismissed. It does no saving, so the caller owns error
/// handling, the duplicate check and the refresh.
///
/// Behaves like the web's AddWordForm / WordEditModal:
/// - leaving the term field looks it up on Jisho, replaces a conjugated form
///   with its dictionary form (担っています → 担う) and fills reading/English
///   only where they're empty, then translates the English;
/// - leaving the English field translates it to Mongolian, unless the English
///   hasn't changed since the last translation (so a hand-typed Mongolian
///   meaning isn't overwritten just by tapping through);
/// - "re-search" (edit only) overwrites term, reading and English from Jisho.
///
/// [draft] edits an unsaved word (the camera capture's review list) the same
/// way [existing] edits a saved one.
Future<WordDraft?> showWordEditor(BuildContext context, {Word? existing, WordDraft? draft}) {
  return showModalBottomSheet<WordDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: WordForm(
        existing: existing,
        draft: draft,
        onSubmit: (draft) => Navigator.of(ctx).pop(draft),
      ),
    ),
  );
}

/// The form itself, reusable inside other sheets (quick add keeps it open
/// between words, so it can't pop on submit).
class WordForm extends ConsumerStatefulWidget {
  const WordForm({
    super.key,
    this.existing,
    this.draft,
    required this.onSubmit,
    this.submitLabel,
    this.busy = false,
  });

  final Word? existing;
  final WordDraft? draft;
  final ValueChanged<WordDraft> onSubmit;
  final String? submitLabel;
  final bool busy;

  @override
  ConsumerState<WordForm> createState() => WordFormState();
}

class WordFormState extends ConsumerState<WordForm> {
  late final _term = TextEditingController(text: widget.existing?.term ?? widget.draft?.term ?? '');
  late final _reading =
      TextEditingController(text: widget.existing?.reading ?? widget.draft?.reading ?? '');
  late final _meaning =
      TextEditingController(text: widget.existing?.meaning ?? widget.draft?.meaning ?? '');
  late final _meaningMn =
      TextEditingController(text: widget.existing?.meaningMn ?? widget.draft?.meaningMn ?? '');
  final _termFocus = FocusNode();
  final _meaningFocus = FocusNode();

  bool _looking = false;
  bool _translating = false;

  /// The English we last translated from.
  late String _lastEn = (widget.existing?.meaning ?? widget.draft?.meaning)?.trim() ?? '';

  /// The term we last looked up, so blurring an unchanged field is free.
  late String _lastLooked = (widget.existing?.term ?? widget.draft?.term)?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _termFocus.addListener(() {
      if (!_termFocus.hasFocus) _lookup();
    });
    _meaningFocus.addListener(() {
      if (!_meaningFocus.hasFocus) _translateIfChanged();
    });
  }

  @override
  void dispose() {
    _term.dispose();
    _reading.dispose();
    _meaning.dispose();
    _meaningMn.dispose();
    _termFocus.dispose();
    _meaningFocus.dispose();
    super.dispose();
  }

  /// Clears the fields after a successful quick-add, keeping the sheet open.
  void reset() {
    _term.clear();
    _reading.clear();
    _meaning.clear();
    _meaningMn.clear();
    _lastEn = '';
    _lastLooked = '';
    _termFocus.requestFocus();
  }

  Future<void> _lookup({bool overwrite = false}) async {
    final t = _term.text.trim();
    if (t.isEmpty || (!overwrite && t == _lastLooked)) return;
    _lastLooked = t;
    setState(() => _looking = true);
    final r = await ref.read(dictionaryProvider).lookup(t);
    if (!mounted) return;
    setState(() => _looking = false);
    if (r.isEmpty) return;
    if (r.word.isNotEmpty && r.word != t) {
      _term.text = r.word;
      _lastLooked = r.word;
    }
    if (r.reading.isNotEmpty && (overwrite || _reading.text.trim().isEmpty)) {
      _reading.text = r.reading;
    }
    if (r.meaning.isNotEmpty && (overwrite || _meaning.text.trim().isEmpty)) {
      _meaning.text = r.meaning;
      await _translate(r.meaning);
    }
  }

  Future<void> _translateIfChanged() async {
    final en = _meaning.text.trim();
    if (en.isNotEmpty && en != _lastEn) await _translate(en);
  }

  Future<void> _translate(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _lastEn = t;
    setState(() => _translating = true);
    final mn = await ref.read(dictionaryProvider).translate(t);
    if (!mounted) return;
    setState(() => _translating = false);
    if (mn.isNotEmpty) _meaningMn.text = mn;
  }

  String? _clean(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    final term = _term.text.trim();
    if (term.isEmpty || widget.busy) return;
    widget.onSubmit(WordDraft(
      term: term,
      reading: _clean(_reading),
      meaning: _clean(_meaning),
      meaningMn: _clean(_meaningMn),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null || widget.draft != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  editing ? T.editWord : T.addWord,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (editing)
                TextButton.icon(
                  onPressed: _looking ? null : () => _lookup(overwrite: true),
                  icon: const Icon(Icons.manage_search, size: 18),
                  label: const Text(T.research),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _term,
            focusNode: _termFocus,
            autofocus: !editing,
            decoration: const InputDecoration(labelText: T.term),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reading,
            decoration: InputDecoration(
              labelText: _looking ? T.lookingUp : T.reading,
              suffixIcon: _looking
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _meaning,
            focusNode: _meaningFocus,
            decoration: const InputDecoration(labelText: T.meaningEn),
            onSubmitted: (_) => _translateIfChanged(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _meaningMn,
            decoration: InputDecoration(
              labelText: T.mongolian,
              suffixIcon: _translating
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.busy ? null : _submit,
            child: Text(widget.submitLabel ?? (editing ? T.save : T.add)),
          ),
        ],
      ),
    );
  }
}
