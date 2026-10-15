import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dictionary.dart';
import '../../core/furigana.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../audio/example_sentences.dart';
import '../review/example_line.dart' show RubySentence;

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
        _lastEn = initial?.en ?? '',
        _furigana = initial?.furigana;

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

  /// The suggestion's reading; kept out of the editable fields, and only
  /// saved while it still describes the sentence.
  String? _furigana;

  /// The search for [_query], kept so a save can finish it after the form
  /// has moved on ([take]).
  Future<Example?>? _found;
  var _seq = 0;
  bool _disposed = false;

  bool get isEmpty =>
      ja.text.trim().isEmpty && en.text.trim().isEmpty && mn.text.trim().isEmpty;

  WordExample get value => WordExample(
        ja: ja.text.trim(),
        en: en.text.trim(),
        mn: mn.text.trim(),
        furigana: furiganaFor(ja.text, _furigana),
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
      _found = null;
      return;
    }
    final found = _found = _sentences.find(q);
    _fetch(found, mine);
  }

  Future<void> _fetch(Future<Example?> found, int mine) async {
    final hit = await found;
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
    _furigana = hit.furigana;
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
    _found = null;
    looking = false;
    none = false;
    _notify();
  }

  /// What to save with [term], without waiting — Tatoeba alone takes 1–4 s,
  /// and the word must not. [now] goes in with the word. [later], when a
  /// sentence or its translation is still on its way, finishes on its own
  /// (even after the form is cleared or closed) for the caller to attach once
  /// it lands (`WordDraft.exampleLater`). A suggestion found for some other
  /// term — the user typed on before it settled — is dropped rather than
  /// saved under the wrong word.
  ({WordExample now, Future<WordExample?>? later}) take(String term) {
    const nothing = WordExample();
    final t = term.trim();
    final stale = t != _context && t != _query;
    final found = _found;
    if (looking && isEmpty) {
      return (now: nothing, later: stale || found == null ? null : _finish(found));
    }
    if (_auto && stale) return (now: nothing, later: null);
    final v = value;
    // Mongolian not in yet: the sentence goes in whole, a moment later.
    if (v.en.isNotEmpty && v.mn.isEmpty) return (now: nothing, later: _translated(v));
    return (now: v, later: null);
  }

  Future<WordExample?> _finish(Future<Example?> found) async {
    final hit = await found;
    return hit == null ? null : _translated(WordExample(ja: hit.ja, en: hit.en, furigana: hit.furigana));
  }

  Future<WordExample> _translated(WordExample v) async =>
      WordExample(ja: v.ja, en: v.en, mn: await _dictionary.translateSentence(v.en), furigana: v.furigana);

  @override
  void dispose() {
    _disposed = true;
    ja.dispose();
    en.dispose();
    mn.dispose();
    super.dispose();
  }
}

/// Collapsed by default to the title and the whole sentence (or why there
/// isn't one), never cut off, so it can be checked without opening. Opened, it
/// reads first: the sentence with furigana and the word picked out, then its
/// translations; editing is a mode you switch into, each field tagged with
/// its language. The web side is ExampleSection.tsx.
class ExampleSection extends StatefulWidget {
  const ExampleSection({
    super.key,
    required this.controller,
    required this.term,
    this.onResearch,
    this.onSubmitted,
  });

  final ExampleController controller;

  /// The word being added or edited, picked out in the sentence.
  final String term;

  /// Fetch a fresh suggestion (Tatoeba), over whatever is there.
  final VoidCallback? onResearch;
  final VoidCallback? onSubmitted;

  @override
  State<ExampleSection> createState() => _ExampleSectionState();
}

class _ExampleSectionState extends State<ExampleSection> {
  var _open = false;
  var _editing = false;
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
        final empty = c.isEmpty;
        // No "searching…" while closed: the field is optional, so nobody
        // needs to watch it fill — the sentence just appears.
        final status = c.looking
            ? ''
            : c.none
                ? T.exampleNone
                : T.exampleEmpty;
        // Nothing to read yet: open straight into the fields.
        final showFields = _editing || (empty && !c.looking);
        final value = c.value;

        Widget icon(IconData i, String tip, VoidCallback? onTap, {bool on = false}) => IconButton(
              tooltip: tip,
              onPressed: onTap,
              visualDensity: VisualDensity.compact,
              iconSize: 19,
              style: on ? IconButton.styleFrom(backgroundColor: hk.sealTint) : null,
              icon: Icon(i, color: on ? hk.sealText : hk.inkMute),
            );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _open ? hk.paperDim.withValues(alpha: 0.3) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _open ? hk.line : hk.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AnimatedRotation(
                                  turns: _open ? 0 : -0.25,
                                  duration: const Duration(milliseconds: 180),
                                  child: Icon(Icons.expand_more, size: 18, color: hk.inkMute),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  T.exampleTitle,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: hk.inkSoft),
                                ),
                                // No sentence yet: the reason sits on the title line.
                                if (!_open && preview.isEmpty && status.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      '  ·  $status',
                                      style: TextStyle(fontSize: 12, color: hk.inkMute),
                                    ),
                                  ),
                              ],
                            ),
                            // Closed, the whole sentence — never cut off. Open, it's right below.
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.topLeft,
                              child: !_open && preview.isNotEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 24, top: 4),
                                      child: Text(preview, style: TextStyle(fontSize: 14, height: 1.4, color: hk.ink)),
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_open) ...[
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: hk.inkMute),
                        ),
                      ),
                    if (widget.onResearch != null)
                      icon(Icons.search, T.exampleSuggest, c.looking
                          ? null
                          : () {
                              setState(() => _editing = false);
                              widget.onResearch!();
                            }),
                    if (!empty)
                      icon(
                        _editing ? Icons.check : Icons.edit_outlined,
                        _editing ? T.exampleDone : T.exampleEdit,
                        () => setState(() => _editing = !_editing),
                        on: _editing,
                      ),
                    if (!empty)
                      icon(Icons.delete_outline, T.exampleClear, () {
                        c.clear();
                        setState(() => _editing = false);
                      }),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: c.looking && empty
                      ? _placeholder(hk)
                      : showFields
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (empty && c.none)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(T.exampleNone, style: TextStyle(fontSize: 12, color: hk.inkMute)),
                                  ),
                                _field(c.ja, T.exampleJa, '日本語', maxLength: 300, big: true),
                                const SizedBox(height: 8),
                                _field(c.en, T.exampleEn, 'EN', focus: _enFocus, maxLength: 500),
                                const SizedBox(height: 8),
                                _field(c.mn, c.translating ? T.lookingUp : T.exampleMn, 'MN',
                                    maxLength: 500, onSubmitted: widget.onSubmitted),
                              ],
                            )
                          : InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => _editing = true),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RubySentence(
                                    ja: value.ja,
                                    furigana: value.furigana,
                                    term: widget.term,
                                    textAlign: TextAlign.start,
                                    style: TextStyle(fontSize: 17, height: 1.4, color: hk.ink),
                                  ),
                                  if (value.mn.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(value.mn, style: TextStyle(fontSize: 14, height: 1.35, color: hk.inkSoft)),
                                    ),
                                  if (value.en.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(value.en, style: TextStyle(fontSize: 12.5, height: 1.35, color: hk.inkMute)),
                                    ),
                                ],
                              ),
                            ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Placeholder lines, the shape of what's coming.
  Widget _placeholder(HankoPalette hk) {
    Widget bar(double f, double h) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: f,
          child: Container(
            height: h,
            decoration: BoxDecoration(color: hk.lineSoft, borderRadius: BorderRadius.circular(4)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [bar(0.8, 16), const SizedBox(height: 8), bar(0.6, 12)]),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    String tag, {
    FocusNode? focus,
    required int maxLength,
    bool big = false,
    VoidCallback? onSubmitted,
  }) {
    final hk = context.hk;
    return TextField(
      controller: ctrl,
      focusNode: focus,
      minLines: 2,
      maxLines: 4,
      maxLength: maxLength,
      style: TextStyle(fontSize: big ? 16 : 14, height: 1.35),
      textInputAction: onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        // The language in the corner, so a filled field still says what it is.
        suffixIcon: Padding(
          padding: const EdgeInsets.only(top: 10, right: 10),
          child: Text(tag, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: hk.inkMute)),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      onChanged: (_) => widget.controller.edited(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
    );
  }
}
