import 'package:flutter/material.dart';

/// The add/edit form for a word, shown as a bottom sheet.
///
/// Returns the entered fields, or null if dismissed. Deliberately dumb — it
/// does no saving, so the caller owns error handling and the list refresh.
class WordDraft {
  const WordDraft({
    required this.term,
    this.reading,
    this.meaning,
    this.meaningMn,
  });

  final String term;
  final String? reading;
  final String? meaning;
  final String? meaningMn;
}

Future<WordDraft?> showWordEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) {
  return showModalBottomSheet<WordDraft>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      // Keeps the fields above the keyboard rather than behind it.
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _WordForm(existing: existing),
    ),
  );
}

class _WordForm extends StatefulWidget {
  const _WordForm({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_WordForm> createState() => _WordFormState();
}

class _WordFormState extends State<_WordForm> {
  late final _term = TextEditingController(
      text: widget.existing?['term'] as String? ?? '');
  late final _reading = TextEditingController(
      text: widget.existing?['reading'] as String? ?? '');
  late final _meaning = TextEditingController(
      text: widget.existing?['meaning'] as String? ?? '');
  late final _meaningMn = TextEditingController(
      text: widget.existing?['meaning_mn'] as String? ?? '');

  @override
  void dispose() {
    _term.dispose();
    _reading.dispose();
    _meaning.dispose();
    _meaningMn.dispose();
    super.dispose();
  }

  void _submit() {
    final term = _term.text.trim();
    if (term.isEmpty) return;
    Navigator.of(context).pop(WordDraft(
      term: term,
      reading: _reading.text.trim().isEmpty ? null : _reading.text.trim(),
      meaning: _meaning.text.trim().isEmpty ? null : _meaning.text.trim(),
      meaningMn: _meaningMn.text.trim().isEmpty ? null : _meaningMn.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            editing ? 'Үг засах' : 'Үг нэмэх',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _term,
            autofocus: !editing,
            decoration: const InputDecoration(
              labelText: 'Үг *',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reading,
            decoration: const InputDecoration(
              labelText: 'Дуудлага',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _meaningMn,
            decoration: const InputDecoration(
              labelText: 'Утга (монгол)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _meaning,
            decoration: const InputDecoration(
              labelText: 'Утга (англи)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              child: Text(editing ? 'Хадгалах' : 'Нэмэх'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
