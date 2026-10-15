import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../../core/dictionary.dart';
import '../../models/library.dart';
import '../audio/example_sentences.dart';
import 'example_section.dart';

export '../../models/library.dart' show WordDraft;

/// The edit form for a word, shown as a bottom sheet. Returns the entered
/// fields, or null if dismissed. It does no saving, so the caller owns error
/// handling and the refresh. (Adding has its own sheet — quick_add_sheet.dart,
/// with live lookups and the handwriting pad, like the web's AddWordModal.)
///
/// Behaves like the web's WordEditModal:
/// - leaving the term field looks it up on Jisho, replaces a conjugated form
///   with its dictionary form (担っています → 担う) and fills reading/English
///   only where they're empty, then translates the English;
/// - leaving the English field translates it to Mongolian, unless the English
///   hasn't changed since the last translation (so a hand-typed Mongolian
///   meaning isn't overwritten just by tapping through);
/// - "re-search" (edit only) overwrites term, reading and English from Jisho.
/// - a saved word gets the example sentence section; one with no sentence
///   yet is offered a suggestion as the form opens. Drafts don't: the
///   camera's outbox doesn't carry sentences.
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

/// The form itself.
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

  /// Only for a saved word (see the class comment).
  late final ExampleController? _example = widget.existing == null
      ? null
      : ExampleController(
          sentences: ref.read(exampleSentencesProvider),
          dictionary: ref.read(dictionaryProvider),
          initial: widget.existing!.example,
        );
  late final _hadExample = widget.existing?.example != null;
  bool _saving = false;

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
    if (_example != null && !_hadExample) _example.suggest(_term.text);
  }

  @override
  void dispose() {
    _term.dispose();
    _reading.dispose();
    _meaning.dispose();
    _meaningMn.dispose();
    _termFocus.dispose();
    _meaningFocus.dispose();
    _example?.dispose();
    super.dispose();
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
    _example?.suggest(r.word.isNotEmpty ? r.word : t);
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

  Future<void> _submit() async {
    final term = _term.text.trim();
    if (term.isEmpty || widget.busy || _saving) return;
    WordExample? example;
    Future<WordExample?>? later;
    final ex = _example;
    if (ex != null) {
      final r = ex.take(term);
      var now = r.now;
      later = r.later;
      // A word that already has a sentence: waiting is rarer than wiping it,
      // since the later save only fills an empty one.
      if (_hadExample && later != null) {
        setState(() => _saving = true);
        now = await later ?? now;
        later = null;
        if (!mounted) return;
        setState(() => _saving = false);
      }
      // Untouched columns stay out of the update (see WordDraft.example).
      if (_hadExample || !now.isEmpty) example = now;
    }
    widget.onSubmit(WordDraft(
      term: term,
      reading: _clean(_reading),
      meaning: _clean(_meaning),
      meaningMn: _clean(_meaningMn),
      example: example,
      exampleLater: later,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null || widget.draft != null;
    // Scrolls: with the example open and the keyboard up it can outgrow
    // the sheet.
    return SingleChildScrollView(
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
          if (_example != null) ...[
            const SizedBox(height: 12),
            ExampleSection(
              controller: _example,
              term: _term.text.trim(),
              onResearch: () => _example.research(_term.text),
              onSubmitted: _submit,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.busy || _saving ? null : _submit,
            child: Text(widget.submitLabel ?? (editing ? T.save : T.add)),
          ),
        ],
      ),
    );
  }
}
