import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dictionary.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../audio/example_sentences.dart';

/// The example sentence part of the add and edit forms (0031): a Tatoeba
/// suggestion for the word with its English translation, the Mongolian
/// machine-translated from the English, all three editable.
///
/// A suggestion only ever lands in fields the user hasn't written in: once
/// they type, the sentence is theirs, and a new term doesn't replace it.
class ExampleController extends ChangeNotifier {
  ExampleController({
    required this._sentences,
    required this._dictionary,
    WordExample? initial,
  })  : ja = TextEditingController(text: initial?.ja ?? ''),
        en = TextEditingController(text: initial?.en ?? ''),
        mn = TextEditingController(text: initial?.mn ?? ''),
        _lastEn = initial?.en ?? '';

  final ExampleSentences _sentences;
  final Dictionary _dictionary;
  final TextEditingController ja, en, mn;

  /// The fields hold a suggestion nobody has edited.
  bool _auto = false;

  /// The word the current suggestion is for, and the term it was asked for
  /// from (the dictionary form vs what was typed).
  String? _query;
  String? _context;

  bool looking = false;

  /// Tatoeba had nothing good for [_query].
  bool none = false;

  bool translating = false;
  String _lastEn;
  Future<void>? _pending;
  var _seq = 0;
  bool _disposed = false;

  bool get isEmpty =>
      ja.text.trim().isEmpty && en.text.trim().isEmpty && mn.text.trim().isEmpty;

  WordExample get value => WordExample(
        ja: ja.text.trim(),
        en: en.text.trim(),
        mn: mn.text.trim(),
      );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Suggest a sentence for [query] (the dictionary form), found while the
  /// user's term was [context]. An empty [query] withdraws a suggestion.
  void suggest(String query, {String? context}) {
    final q = query.trim();
    if (!_auto && !isEmpty) return;
    _context = context ?? q;
    if (q == _query) return;
    _query = q;
    final mine = ++_seq;
    if (_auto) _set(const WordExample());
    _auto = false;
    none = false;
    looking = q.isNotEmpty;
    _notify();
    if (q.isEmpty) {
      _pending = null;
      return;
    }
    _pending = _fetch(q, mine);
  }

  Future<void> _fetch(String q, int mine) async {
    final hit = await _sentences.find(q);
    if (_disposed || mine != _seq) return;
    looking = false;
    if (!isEmpty) {
      _notify();
      return; // typed in while we waited: theirs wins
    }
    if (hit == null) {
      none = true;
      _notify();
      return;
    }
    _set(WordExample(ja: hit.ja, en: hit.en));
    _auto = true;
    _notify();
    await _translate(hit.en, mine);
  }

  void _set(WordExample e) {
    ja.text = e.ja;
    en.text = e.en;
    mn.text = e.mn;
  }

  /// A field the user typed into: the sentence is theirs now.
  void edited() {
    if (_auto) {
      _auto = false;
      _notify();
    }
  }

  /// English edited by hand gets a fresh Mongolian translation, as the
  /// word's own meaning does.
  Future<void> englishLeft() async {
    final t = en.text.trim();
    if (t.isEmpty || t == _lastEn) return;
    await _translate(t, _seq);
  }

  Future<void> _translate(String text, int mine) async {
    _lastEn = text;
    translating = true;
    _notify();
    final out = await _dictionary.translateSentence(text);
    if (_disposed) return;
    translating = false;
    if (out.isNotEmpty && mine == _seq && en.text.trim() == text) mn.text = out;
    _notify();
  }

  /// Fetch a suggestion even over what's there (the edit form's button).
  void research(String term) {
    _set(const WordExample());
    _auto = true;
    _query = null;
    suggest(term);
  }

  void clear() {
    _seq++;
    _set(const WordExample());
    _auto = false;
    _query = null;
    _context = null;
    looking = false;
    none = false;
    _notify();
  }

  /// What to save with [term]: waits a moment for a suggestion or a
  /// translation still on its way. A suggestion found for some other term —
  /// the user typed on before it settled — is dropped rather than saved
  /// under the wrong word.
  Future<WordExample> settle(String term) async {
    final p = _pending;
    if (p != null && looking) {
      await p.timeout(const Duration(seconds: 6), onTimeout: () {});
    }
    if (_auto && term.trim() != _context && term.trim() != _query) {
      return const WordExample();
    }
    if (en.text.trim().isNotEmpty && mn.text.trim().isEmpty) {
      final out = await _dictionary.translateSentence(en.text.trim());
      if (out.isNotEmpty) mn.text = out;
    }
    return value;
  }

  @override
  void dispose() {
    _disposed = true;
    ja.dispose();
    en.dispose();
    mn.dispose();
    super.dispose();
  }
}

/// Collapsed by default — one line with the sentence (or why there isn't
/// one) — so a word with a sentence costs the form a single row. Tapping it
/// opens the three fields.
class ExampleSection extends StatefulWidget {
  const ExampleSection({super.key, required this.controller, this.onResearch, this.onSubmitted});

  final ExampleController controller;

  /// Shown as a button when open (the edit form): fetch a new suggestion.
  final VoidCallback? onResearch;
  final VoidCallback? onSubmitted;

  @override
  State<ExampleSection> createState() => _ExampleSectionState();
}

class _ExampleSectionState extends State<ExampleSection> {
  var _open = false;
  final _enFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _enFocus.addListener(() {
      if (!_enFocus.hasFocus) widget.controller.englishLeft();
    });
  }

  @override
  void dispose() {
    _enFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final busy = c.looking || c.translating;
        final preview = c.ja.text.trim();
        final status = preview.isNotEmpty
            ? preview
            : c.looking
                ? T.lookingUp
                : c.none
                    ? T.exampleNone
                    : T.exampleEmpty;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hk.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Icon(Icons.format_quote_rounded, size: 18, color: hk.inkMute),
                      const SizedBox(width: 6),
                      Text(
                        T.exampleTitle,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: hk.inkSoft),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: preview.isNotEmpty ? hk.ink : hk.inkMute,
                          ),
                        ),
                      ),
                      if (busy)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: hk.inkMute),
                          ),
                        ),
                      Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: hk.inkMute),
                    ],
                  ),
                ),
              ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(c.ja, T.exampleJa, maxLength: 300),
                      const SizedBox(height: 10),
                      _field(c.en, T.exampleEn, focus: _enFocus, maxLength: 500),
                      const SizedBox(height: 10),
                      _field(c.mn, T.exampleMn, maxLength: 500, onSubmitted: widget.onSubmitted),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.onResearch != null)
                            TextButton.icon(
                              onPressed: c.looking ? null : widget.onResearch,
                              icon: const Icon(Icons.manage_search, size: 18),
                              label: const Text(T.exampleSuggest),
                            ),
                          if (!c.isEmpty)
                            TextButton(onPressed: c.clear, child: const Text(T.exampleClear)),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    FocusNode? focus,
    required int maxLength,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focus,
      minLines: 1,
      maxLines: 3,
      maxLength: maxLength,
      textInputAction: onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
      onChanged: (_) => widget.controller.edited(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
    );
  }
}
