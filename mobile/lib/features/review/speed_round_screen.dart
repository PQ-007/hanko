import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/repository.dart';
import '../../models/queue_card.dart';

const _uuid = Uuid();

/// Speed round: a quick pass over already-mature cards, purely for
/// reinforcement. Every answer is logged with `source: 'drill'`
/// (`review_card()`'s non-review branch — see 0009_review_card.sql), which the
/// server returns completely untouched: no interval change, no due date
/// change, nothing for undo to restore. That is what makes this screen simpler
/// than ReviewScreen — there is no scheduling state to protect, so there is no
/// offline queue and no undo, just "did you get it or not".
///
/// Deliberately online-only: this is an opt-in bonus session, not the
/// day's scheduled workload, so failing outright when offline is an
/// acceptable, honest limit rather than more machinery to maintain.
class SpeedRoundScreen extends ConsumerStatefulWidget {
  const SpeedRoundScreen({super.key, this.deckId});
  final String? deckId;

  @override
  ConsumerState<SpeedRoundScreen> createState() => _SpeedRoundScreenState();
}

class _SpeedRoundScreenState extends ConsumerState<SpeedRoundScreen> {
  List<QueueCard>? _queue;
  bool _revealed = false;
  int _correct = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cards =
          await ref.read(repositoryProvider).matureCards(deckId: widget.deckId);
      if (!mounted) return;
      setState(() => _queue = cards);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _answer(bool correct) async {
    final card = _queue!.first;
    setState(() {
      _revealed = false;
      _total += 1;
      if (correct) _correct += 1;
      _queue = _queue!.skip(1).toList();
    });
    // Fire-and-forget: a dropped log here loses one drill row, not scheduling
    // state, so the round is not held up waiting on it.
    unawaited(ref.read(repositoryProvider).reviewCard(
          cardId: card.cardId,
          rating: correct ? 'good' : 'again',
          logId: _uuid.v4(),
          source: 'drill',
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Хурдан давталт')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Ачааллаж чадсангүй:\n$_error'),
        )),
      );
    }
    if (_queue == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_queue!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Хурдан давталт')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_total == 0 ? '🙂' : '🎉', style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  _total == 0
                      ? 'Эзэмшсэн үг алга байна'
                      : 'Дууслаа! $_correct / $_total зөв',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (_total == 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Хурдан давталт нь 21+ өдрийн интервалтай үгсийг ашигладаг.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final card = _queue!.first;
    return Scaffold(
      appBar: AppBar(
        title: Text('Хурдан давталт · ${_queue!.length}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_total > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Text('$_correct / $_total',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _revealed = true),
                  child: Card(
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 220),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(card.term,
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center),
                          if (_revealed) ...[
                            const SizedBox(height: 12),
                            if (card.reading != null && card.reading != card.term)
                              Text(card.reading!,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(color: Colors.grey)),
                            if (card.meaningMn != null && card.meaningMn!.isNotEmpty)
                              Text(card.meaningMn!, style: theme.textTheme.bodyLarge),
                            if (card.meaning != null && card.meaning!.isNotEmpty)
                              Text(card.meaning!,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: Colors.grey)),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text('Товшиж хариултыг харах',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_revealed)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _answer(false),
                      child: const Text('Буруу'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _answer(true),
                      child: const Text('Зөв'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => setState(() => _revealed = true),
                  child: const Text('Харах'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
