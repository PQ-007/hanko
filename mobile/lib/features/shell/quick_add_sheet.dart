import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_router.dart';
import '../../core/dictionary.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../audio/example_sentences.dart';
import '../decks/add_word_rules.dart';
import '../decks/example_section.dart';
import '../decks/handwriting_pad.dart';
import '../decks/word_actions.dart';

/// Same key name as the web (AddWordModal.tsx): per-device is the honest
/// scope for a convenience no other client reads.
/// The camera capture shares it, so both remember one "last deck".
const quickAddDeckKey = 'hanko.quickAdd.deck';

/// Whether the handwriting pad was open last time (web: hanko.addWord.pad).
const _padKey = 'hanko.addWord.pad';

/// Add words — from a deck ([lockDeck]: that deck, no picker) or from
/// anywhere else (a picker that remembers the last deck). One sheet for
/// both, the mobile side of the web's AddWordModal.tsx:
///
/// - The term is looked up on Jisho as it changes and the matches are listed
///   to pick from; the best one fills reading and meaning straight away, but
///   only fields the user hasn't written themselves (add_word_rules.dart).
///   The keyboard's done key — or moving on to another field — swaps it for
///   the dictionary form (担っています → 担う); never mid-typing.
/// - A handwriting pad (ML Kit, on the phone) for kanji the user can read
///   but can't type.
/// - An example sentence for the word (Tatoeba, with its translations),
///   collapsed to one line under the details (example_section.dart).
/// - It stays open after each add, with the Add button pinned to the bottom.
Future<void> showQuickAddSheet(
  BuildContext context,
  WidgetRef ref, {
  String? deckId,
  bool lockDeck = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AddWordSheet(initialDeckId: deckId, lockDeck: lockDeck && deckId != null),
    ),
  );
}

class _AddWordSheet extends ConsumerStatefulWidget {
  const _AddWordSheet({this.initialDeckId, required this.lockDeck});
  final String? initialDeckId;
  final bool lockDeck;

  @override
  ConsumerState<_AddWordSheet> createState() => _AddWordSheetState();
}

class _AddWordSheetState extends ConsumerState<_AddWordSheet> {
  /// Long enough that a lookup isn't sent per keystroke, short enough to feel live.
  static const _lookupDelay = Duration(milliseconds: 400);

  final _term = TextEditingController();
  final _reading = TextEditingController();
  final _meaning = TextEditingController();
  final _meaningMn = TextEditingController();
  final _termFocus = FocusNode();
  final _readingFocus = FocusNode();
  final _meaningFocus = FocusNode();
  final _mnFocus = FocusNode();
  late final _example = ExampleController(
    sentences: ref.read(exampleSentencesProvider),
    dictionary: ref.read(dictionaryProvider),
  );

  String? _deckId;
  var _auto = <AutoKey>{};
  ({String term, List<LookupResult> list})? _matches;
  final _cache = <String, List<LookupResult>>{};
  var _looking = false;
  Timer? _lookupTimer;
  var _lookupSeq = 0;

  /// The term a match was explicitly picked for: later lookups of that same
  /// term mustn't swap the pick (生 read なま) back to the best match (せい).
  String? _pinnedFor;

  /// The done key came before the matches did: accept the best on arrival.
  String? _pendingAccept;

  /// English the Mongolian was last translated from, and English whose
  /// translation came back empty (so the field stops saying "translating").
  var _lastEn = '';
  String? _mnFailedFor;
  String? _translatingFor;

  var _padOpen = false;
  var _busy = false;
  final _added = <String>[];
  String? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _deckId = widget.initialDeckId;
    _restorePrefs();
    // Moving on to another field takes the dictionary form, like the web's Tab.
    for (final f in [_readingFocus, _meaningFocus, _mnFocus]) {
      f.addListener(() {
        if (f.hasFocus) _acceptBest();
      });
    }
    _meaningFocus.addListener(() {
      if (!_meaningFocus.hasFocus) _translateEdited();
    });
  }

  Future<void> _restorePrefs() async {
    var pad = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      pad = prefs.getBool(_padKey) ?? false;
      final stored = prefs.getString(quickAddDeckKey);
      if (!widget.lockDeck && widget.initialDeckId == null && stored != null) _deckId = stored;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _padOpen = pad);
    // With the pad open the keyboard would only cover it.
    if (!pad) _termFocus.requestFocus();
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    _flashTimer?.cancel();
    for (final c in [_term, _reading, _meaning, _meaningMn]) {
      c.dispose();
    }
    for (final f in [_termFocus, _readingFocus, _meaningFocus, _mnFocus]) {
      f.dispose();
    }
    _example.dispose();
    super.dispose();
  }

  // ---- Fields ----------------------------------------------------------------

  WordFields get _fields => WordFields(
    term: _term.text,
    reading: _reading.text,
    meaning: _meaning.text,
    meaningMn: _meaningMn.text,
  );

  /// Writes [f] into the controllers (only where it differs, so a caret isn't
  /// disturbed for nothing) and starts a translation the new state needs.
  void _apply(WordFields f, Set<AutoKey> auto) {
    void put(TextEditingController c, String v) {
      if (c.text != v) c.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
    }

    put(_term, f.term);
    put(_reading, f.reading);
    put(_meaning, f.meaning);
    put(_meaningMn, f.meaningMn);
    setState(() => _auto = auto);
    _autoTranslate();
  }

  /// A field the user typed into is theirs from now on.
  void _edited(AutoKey k) {
    if (_auto.contains(k)) setState(() => _auto = {..._auto}..remove(k));
  }

  bool get _needMn =>
      _auto.contains(AutoKey.meaning) &&
      _auto.contains(AutoKey.meaningMn) &&
      _meaningMn.text.isEmpty &&
      _meaning.text.trim().isNotEmpty;

  bool get _translating => _needMn && _mnFailedFor != _meaning.text;

  /// A machine-filled English meaning gets its Mongolian automatically,
  /// unless the user has written their own; dropped if the English moved on.
  Future<void> _autoTranslate() async {
    if (!_needMn) return;
    final en = _meaning.text;
    if (_translatingFor == en) return;
    _translatingFor = en;
    final mn = await ref.read(dictionaryProvider).translate(en);
    if (!mounted) return;
    if (_translatingFor == en) _translatingFor = null;
    if (mn.isEmpty) {
      setState(() => _mnFailedFor = en);
      return;
    }
    if (_meaning.text == en && _auto.contains(AutoKey.meaningMn) && _meaningMn.text.isEmpty) {
      _lastEn = en.trim();
      setState(() => _meaningMn.text = mn);
    }
  }

  /// Hand-edited English: translated when the field is left, as the edit
  /// form does.
  Future<void> _translateEdited() async {
    final en = _meaning.text.trim();
    if (en.isEmpty || en == _lastEn) return;
    _lastEn = en;
    final mn = await ref.read(dictionaryProvider).translate(en);
    if (!mounted || mn.isEmpty) return;
    setState(() {
      _meaningMn.text = mn;
      _auto = {..._auto, AutoKey.meaningMn};
    });
  }

  // ---- Lookup ----------------------------------------------------------------

  String get _termKey => _term.text.trim();

  /// Looks the term up after a pause. Not mid-IME-composition: that's kana on
  /// its way to being the word.
  void _scheduleLookup() {
    _lookupTimer?.cancel();
    final composing = _term.value.composing;
    final term = _termKey;
    if (term.isEmpty || (composing.isValid && !composing.isCollapsed)) {
      setState(() => _looking = false);
      return;
    }
    final hit = _cache[term];
    if (hit != null) {
      _onMatches(term, hit);
      return;
    }
    final mine = ++_lookupSeq;
    _lookupTimer = Timer(_lookupDelay, () async {
      // Tatoeba alongside Jisho rather than after it: most terms are typed
      // in dictionary form already, so this usually saves Jisho's 1–2 s. A
      // different dictionary form re-asks in _onMatches.
      if (_pinnedFor != term) _example.suggest(term, context: term);
      setState(() => _looking = true);
      final list = await ref.read(dictionaryProvider).tryLookupAll(term);
      if (!mounted || mine != _lookupSeq) return;
      setState(() => _looking = false);
      // Only a real answer is remembered; a failed request should be retried.
      if (list != null) _cache[term] = list;
      _onMatches(term, list ?? const []);
    });
  }

  void _onMatches(String term, List<LookupResult> list) {
    setState(() => _matches = (term: term, list: list));
    final best = list.firstOrNull;
    if (_termKey != term) return;
    // The sentence is for the dictionary form, and only for a real word.
    if (_pinnedFor != term) _example.suggest(best?.word ?? '', context: term);
    if (best == null) return;
    if (_pendingAccept == term) {
      _pendingAccept = null;
      if (_pinnedFor != term) _accept(best, term);
      return;
    }
    if (_pinnedFor == term) return;
    final r = autofill(_fields, _auto, best);
    _apply(r.fields, r.auto);
  }

  /// The dictionary form replaces the term, the rest by the usual rules —
  /// unless the term changed since [m] was looked up for it.
  void _accept(LookupResult m, String forTerm) {
    if (_termKey != forTerm) return;
    final r = autofill(_fields.copyWith(term: m.word), _auto, m);
    _apply(r.fields, r.auto);
    if (m.word != forTerm) _scheduleLookup();
  }

  /// A tap on a match: it wins outright, over anything typed.
  void _choose(LookupResult m) {
    _pinnedFor = m.word;
    _example.suggest(m.word);
    final keepMn = _meaning.text == m.meaning;
    final auto = {AutoKey.reading, AutoKey.meaning};
    if (!keepMn || _auto.contains(AutoKey.meaningMn)) auto.add(AutoKey.meaningMn);
    _apply(
      WordFields(term: m.word, reading: m.reading, meaning: m.meaning, meaningMn: keepMn ? _meaningMn.text : ''),
      auto,
    );
    _scheduleLookup();
  }

  void _acceptBest() {
    final term = _termKey;
    if (term.isEmpty) return;
    final m = _matches;
    if (m == null || m.term != term) {
      _pendingAccept = term;
      return;
    }
    final best = m.list.firstOrNull;
    if (best != null && _pinnedFor != term) _accept(best, term);
  }

  /// The done key: first press takes the dictionary form; once the term is
  /// it, the next adds.
  void _termDone() {
    final term = _termKey;
    if (term.isEmpty) return;
    final m = _matches;
    if (m == null || m.term != term) {
      _pendingAccept = term;
      return;
    }
    final best = m.list.firstOrNull;
    if (best != null && _pinnedFor != term && best.word != term) {
      _accept(best, term);
      return;
    }
    _add();
  }

  /// A character from the pad goes where the caret is (the end, if the field
  /// was never touched) — without focusing the field, which would bring the
  /// keyboard up over the pad.
  void _insertDrawn(String s) {
    final v = _term.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, s);
    _term.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: sel.start + s.length));
    setState(() {});
    _scheduleLookup();
  }

  String get _preContext {
    final v = _term.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    return v.text.substring(0, at.clamp(0, v.text.length));
  }

  void _clear() {
    _reset();
    if (!_padOpen) _termFocus.requestFocus();
  }

  void _reset() {
    _lookupTimer?.cancel();
    _lookupSeq++;
    _pinnedFor = null;
    _pendingAccept = null;
    _lastEn = '';
    _mnFailedFor = null;
    _matches = null;
    _looking = false;
    _example.clear();
    _apply(const WordFields(), {});
  }

  Future<void> _togglePad() async {
    final open = !_padOpen;
    setState(() => _padOpen = open);
    if (open) FocusScope.of(context).unfocus();
    try {
      (await SharedPreferences.getInstance()).setBool(_padKey, open);
    } catch (_) {}
  }

  Future<void> _pickDeck(String id) async {
    setState(() => _deckId = id);
    try {
      (await SharedPreferences.getInstance()).setString(quickAddDeckKey, id);
    } catch (_) {}
  }

  // ---- Saving ----------------------------------------------------------------

  Future<void> _add() async {
    final term = _termKey;
    final decks = ref.read(decksProvider).value ?? const [];
    final deckId = decks.any((d) => d.id == _deckId) ? _deckId! : decks.firstOrNull?.id;
    if (term.isEmpty || deckId == null || _busy) return;
    setState(() => _busy = true);
    final meaning = _meaning.text.trim();
    // Added before its translation came back: wait for it rather than save a
    // word with no Mongolian meaning.
    final mn = _meaningMn.text.trim().isNotEmpty
        ? _meaningMn.text.trim()
        : (meaning.isEmpty ? '' : await ref.read(dictionaryProvider).translate(meaning));
    // Never waits for the sentence: one still on its way lands afterwards.
    final example = _example.take(term);
    if (!mounted) return;
    final reading = _reading.text.trim();
    final saved = await addWordChecked(
      context,
      ref,
      deckId: deckId,
      draft: WordDraft(
        term: term,
        reading: reading.isEmpty ? null : reading,
        meaning: meaning.isEmpty ? null : meaning,
        meaningMn: mn.isEmpty ? null : mn,
        example: example.now,
        exampleLater: example.later,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!saved) return;
    _flashTimer?.cancel();
    setState(() {
      _added.insert(0, term);
      _flash = term;
    });
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flash = null);
    });
    _reset();
    if (!_padOpen) _termFocus.requestFocus();
  }

  // ---- UI ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).value ?? const <Deck>[];
    final hk = context.hk;

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
    final deck = decks.where((d) => d.id == _deckId).firstOrNull ?? decks.first;
    final shown = _termKey.isEmpty ? null : _matches;
    final stale = shown != null && shown.term != _termKey;
    final picked = shown == null ? null : pickedMatch(_fields, shown.list);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(hk, decks, deck),
        Divider(height: 1, color: hk.lineSoft),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(hk, T.addTermLabel),
                Row(
                  children: [
                    Expanded(child: _termField(hk)),
                    const SizedBox(width: 8),
                    _padToggle(hk),
                  ],
                ),
                if (_padOpen) ...[
                  const SizedBox(height: 14),
                  HandwritingPad(preContext: _preContext, onPick: _insertDrawn),
                ],
                if (shown != null) ...[
                  const SizedBox(height: 16),
                  AnimatedOpacity(
                    opacity: stale ? 0.5 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: _matchList(hk, shown.list, picked),
                  ),
                ],
                const SizedBox(height: 16),
                _details(hk),
                const SizedBox(height: 12),
                ExampleSection(
                  controller: _example,
                  term: _termKey,
                  onResearch: () => _example.research(_termKey),
                  onSubmitted: _add,
                ),
              ],
            ),
          ),
        ),
        _footer(hk),
      ],
    );
  }

  Widget _header(HankoPalette hk, List<Deck> decks, Deck deck) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(T.quickAddTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (widget.lockDeck)
                      Text(deck.name, style: TextStyle(fontSize: 12, color: hk.inkMute), overflow: TextOverflow.ellipsis)
                    else
                      Row(
                        children: [
                          Text('${T.quickAddDeckLabel} ', style: TextStyle(fontSize: 12, color: hk.inkMute)),
                          Flexible(
                            child: DropdownButton<String>(
                              value: deck.id,
                              isDense: true,
                              isExpanded: true,
                              underline: const SizedBox(),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: hk.ink),
                              items: [
                                for (final d in decks)
                                  DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (v) {
                                if (v != null) _pickDeck(v);
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: T.closeLabel,
                icon: Icon(Icons.close, color: hk.inkMute),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (_added.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 26,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Center(
                    child: Row(
                      children: [
                        Icon(Icons.check, size: 14, color: hk.sealText),
                        const SizedBox(width: 2),
                        Text(
                          '${_added.length}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hk.sealText),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                  for (var i = 0; i < _added.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _AddedChip(key: ValueKey(_added.length - i), term: _added[i], fresh: i == 0),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(HankoPalette hk, String text, {AutoKey? auto, bool busy = false}) {
    final isAuto = auto != null && _auto.contains(auto) && _fields[auto].isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: hk.inkSoft)),
          const SizedBox(width: 6),
          if (busy)
            SizedBox.square(dimension: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: hk.inkMute))
          else if (isAuto)
            Tooltip(
              message: T.autoFilledTitle,
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 11, color: hk.sealText),
                  const SizedBox(width: 2),
                  Text(
                    T.autoFilled,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: hk.sealText),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _termField(HankoPalette hk) {
    return TextField(
      controller: _term,
      focusNode: _termFocus,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        hintText: '勉強',
        hintStyle: TextStyle(fontWeight: FontWeight.w400, color: hk.inkMute.withValues(alpha: 0.5)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffixIconConstraints: const BoxConstraints(minHeight: 36),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_looking)
              SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: hk.inkMute)),
            if (_term.text.isNotEmpty)
              IconButton(
                tooltip: T.clearForm,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: hk.inkMute),
                onPressed: _clear,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
      onChanged: (_) {
        setState(() {});
        _scheduleLookup();
      },
      onSubmitted: (_) => _termDone(),
      // Keep the keyboard up between words.
      onEditingComplete: () {},
    );
  }

  Widget _padToggle(HankoPalette hk) {
    return Tooltip(
      message: T.handwrite,
      child: Material(
        color: _padOpen ? hk.sealTint : hk.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _padOpen ? hk.seal : hk.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _togglePad,
          child: SizedBox.square(
            dimension: 48,
            child: Icon(Icons.draw_outlined, size: 22, color: _padOpen ? hk.sealText : hk.inkSoft),
          ),
        ),
      ),
    );
  }

  Widget _matchList(HankoPalette hk, List<LookupResult> list, LookupResult? picked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(hk, T.addMatches),
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hk.line),
            ),
            child: Text(T.addMatchesNone, style: TextStyle(fontSize: 12, color: hk.inkMute)),
          )
        else
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _MatchRow(match: m, picked: identical(m, picked), onTap: () => _choose(m)),
            ),
      ],
    );
  }

  Widget _details(HankoPalette hk) {
    InputDecoration deco([String? hint]) => InputDecoration(
      isDense: true,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hk.paperDim.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hk.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(hk, T.reading, auto: AutoKey.reading),
          TextField(
            controller: _reading,
            focusNode: _readingFocus,
            decoration: deco(),
            textInputAction: TextInputAction.next,
            onChanged: (_) => _edited(AutoKey.reading),
          ),
          const SizedBox(height: 12),
          _label(hk, T.meaningEn, auto: AutoKey.meaning),
          TextField(
            controller: _meaning,
            focusNode: _meaningFocus,
            decoration: deco(),
            textInputAction: TextInputAction.next,
            onChanged: (_) => _edited(AutoKey.meaning),
          ),
          const SizedBox(height: 12),
          _label(hk, T.mongolian, auto: AutoKey.meaningMn, busy: _translating),
          TextField(
            controller: _meaningMn,
            focusNode: _mnFocus,
            decoration: deco(_translating ? T.lookingUp : null),
            textInputAction: TextInputAction.done,
            onChanged: (_) => _edited(AutoKey.meaningMn),
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
    );
  }

  Widget _footer(HankoPalette hk) {
    final canAdd = _termKey.isNotEmpty && !_busy;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hk.card,
        border: Border(top: BorderSide(color: hk.lineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text(T.quickAddDone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canAdd ? _add : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    // Faded accent rather than the theme's grey: a disabled
                    // Add still reads as this sheet's main action.
                    disabledBackgroundColor: hk.seal.withValues(alpha: 0.4),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
                  ),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_flash != null ? Icons.check : Icons.add, size: 18),
                  label: Text(
                    _flash != null ? T.addedFlash(_flash!) : T.addWord,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One Jisho match: word and reading stacked, meaning beside, a radio mark.
class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.picked, required this.onTap});
  final LookupResult match;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final m = match;
    return Material(
      color: picked ? hk.sealTint.withValues(alpha: 0.6) : hk.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: picked ? hk.seal : hk.lineSoft),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.word, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: hk.ink)),
                  if (m.reading.isNotEmpty && m.reading != m.word)
                    Text(m.reading, style: TextStyle(fontSize: 11, color: hk.inkMute)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  m.meaning,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.3, color: hk.inkSoft),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: picked ? hk.seal : null,
                  border: Border.all(color: picked ? hk.seal : hk.line),
                ),
                child: picked ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A word added this session; the newest pops in.
class _AddedChip extends StatelessWidget {
  const _AddedChip({super.key, required this.term, required this.fresh});
  final String term;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: fresh ? hk.sealTint : hk.paper,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: fresh ? hk.seal.withValues(alpha: 0.4) : hk.lineSoft),
      ),
      child: Text(term, style: TextStyle(fontSize: 12, color: fresh ? hk.ink : hk.inkSoft)),
    );
    if (!fresh) return Center(child: chip);
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => Opacity(opacity: ((v - 0.6) / 0.4).clamp(0, 1), child: Transform.scale(scale: v, child: child)),
        child: chip,
      ),
    );
  }
}
