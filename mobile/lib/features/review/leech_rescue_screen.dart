import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/repository.dart';
import '../../models/queue_card.dart';
import 'srs_preview.dart';

const _uuid = Uuid();

class _Answered {
  const _Answered(this.logId, this.card);
  final String logId;
  final QueueCard card;
}

/// A focused session over high-lapse cards ("leeches" — Anki's term for a
/// card that keeps failing), reached before the scheduler would normally
/// surface them again.
///
/// Unlike the speed round, answers here use the default `source: 'review'`:
/// a successful rescue is real practice and genuinely reschedules the card,
/// same as if it had come up in the ordinary due queue — this screen only
/// changes *which* cards you see, not what answering them means. That is also
/// why undo goes through `undoReview()` rather than the offline outbox: there
/// is a real log row on the server the moment an answer lands, exactly as in
/// the main review screen, just without the offline-queue path — this is a
/// proactive, online-only session, not part of today's guaranteed workload.
class LeechRescueScreen extends ConsumerStatefulWidget {
  const LeechRescueScreen({super.key, this.deckId});
  final String? deckId;

  @override
  ConsumerState<LeechRescueScreen> createState() => _LeechRescueScreenState();
}

class _LeechRescueScreenState extends ConsumerState<LeechRescueScreen> {
  List<QueueCard>? _queue;
  bool _revealed = false;
  int _reviewed = 0;
  final List<_Answered> _history = [];
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cards =
          await ref.read(repositoryProvider).leechCards(deckId: widget.deckId);
      if (!mounted) return;
      setState(() => _queue = cards);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _rate(String rating) async {
    if (_sending || _queue == null || _queue!.isEmpty) return;
    final card = _queue!.first;
    final logId = _uuid.v4();
    setState(() => _sending = true);
    try {
      await ref.read(repositoryProvider).reviewCard(
            cardId: card.cardId,
            rating: rating,
            logId: logId,
          );
      if (!mounted) return;
      setState(() {
        _revealed = false;
        _reviewed += 1;
        _history.add(_Answered(logId, card));
        _queue = _queue!.skip(1).toList();
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _sending = false;
      });
    }
  }

  Future<void> _undo() async {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    setState(() {
      _reviewed = _reviewed > 0 ? _reviewed - 1 : 0;
      _queue = [last.card, ...?_queue];
      _revealed = true;
    });
    try {
      await ref.read(repositoryProvider).undoReview(last.logId);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null && _queue == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leech аврах')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Ачааллаж чадсангүй:\n$_error'),
          ),
        ),
      );
    }
    if (_queue == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_queue!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leech аврах')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_reviewed == 0 ? '👍' : '🎉', style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  _reviewed == 0
                      ? 'Одоогоор leech алга байна'
                      : '$_reviewed үг аварлаа!',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (_reviewed == 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Leech гэдэг нь дахин дахин алдаж байгаа үг.',
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
        title: Text('Leech аврах · ${_queue!.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _history.isEmpty ? null : _undo,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                color: Colors.red.shade50,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                child: Text('$_error',
                    style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
              ),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _revealed = true),
                  child: Card(
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 200),
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
                          ],
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
                  for (final rating in const ['again', 'hard', 'good', 'easy'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _RescueButton(
                          rating: rating,
                          card: card,
                          onPressed: _sending ? null : () => _rate(rating),
                        ),
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

class _RescueButton extends StatelessWidget {
  const _RescueButton({required this.rating, required this.card, this.onPressed});
  final String rating;
  final QueueCard card;
  final VoidCallback? onPressed;

  static const _labels = {'again': 'Дахин', 'hard': 'Хэцүү', 'good': 'Сайн', 'easy': 'Амархан'};
  static const _colors = {
    'again': Colors.red,
    'hard': Colors.orange,
    'good': Colors.blue,
    'easy': Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[rating]!;
    final preview = previewNext(
      state: card.state,
      learningStep: card.learningStep,
      intervalDays: card.intervalDays,
      repetitions: card.repetitions,
      easeFactor: card.easeFactor,
      rating: rating,
    );
    final label = preview.unit == PreviewUnit.minutes
        ? '${preview.value} мин'
        : '${preview.value} өд';
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_labels[rating]!, style: const TextStyle(fontSize: 13)),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
