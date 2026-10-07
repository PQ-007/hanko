import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/strings.dart';

// Must match profiles_new_per_day_check (0023): a value the UI accepts but
// the database rejects would read as a save that silently did nothing.
const _min = 0;
const _max = 999;

/// Sets `profiles.new_per_day` — the same daily cap the scheduler enforces,
/// surfaced as a goal (web GoalModal.tsx).
Future<void> showGoalDialog(BuildContext context, WidgetRef ref, int current) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _GoalDialog(current: current),
  );
  if (saved == true) ref.invalidate(dueSummaryProvider);
}

class _GoalDialog extends ConsumerStatefulWidget {
  const _GoalDialog({required this.current});
  final int current;

  @override
  ConsumerState<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends ConsumerState<_GoalDialog> {
  late final _controller = TextEditingController(text: '${widget.current}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _value {
    final v = int.tryParse(_controller.text.trim());
    if (v == null || v < _min || v > _max) return null;
    return v;
  }

  Future<void> _save() async {
    final v = _value;
    if (v == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).setNewPerDay(v);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${T.goalSaveFailed} $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(T.goalModalTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(T.goalModalDesc),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: T.goalModalLabel),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(T.cancel)),
        FilledButton(
          onPressed: _busy || _value == null ? null : _save,
          child: const Text(T.save),
        ),
      ],
    );
  }
}
