import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository.dart';
import '../../models/queue_card.dart';
import '../review/review_screen.dart';
import '../settings/reminder_tile.dart';
import '../stats/stats_screen.dart';
import 'deck_detail_screen.dart';

final _decksProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(repositoryProvider).decks(),
);

final _dueProvider = FutureProvider<DueSummary>(
  (ref) => ref.watch(repositoryProvider).dueSummary(),
);

/// Deck list plus today's workload. Deliberately thin: it proves the whole
/// chain end to end — auth, RLS, and the two server-side RPCs — before any
/// review UI is built on top of it.
class DeckListScreen extends ConsumerStatefulWidget {
  const DeckListScreen({super.key});

  @override
  ConsumerState<DeckListScreen> createState() => _DeckListScreenState();
}

class _DeckListScreenState extends ConsumerState<DeckListScreen> {
  @override
  void initState() {
    super.initState();
    // The SRS day boundary is evaluated server-side in this timezone. Phones
    // are the one client that actually changes timezone, so this matters more
    // here than on the web.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final tz = await FlutterTimezone.getLocalTimezone();
        await ref.read(repositoryProvider).syncTimezone(tz.identifier);
      } catch (_) {
        // Non-fatal: the server falls back to UTC.
      }
      // Re-forecast the reminder against current state. Doing it here means
      // the count refreshes on every app open, including right after a session
      // — otherwise tonight's reminder would still quote this morning's
      // backlog.
      try {
        final reminders = await ref.read(remindersProvider.future);
        await reminders.reschedule();
      } catch (_) {
        // A reminder that fails to reschedule must never block the deck list.
      }
    });
  }

  /// Both providers are invalidated on the way back: a finished session changes
  /// what's due, and a stale count here would contradict the session the user
  /// just completed.
  Future<void> _startReview(
    BuildContext context,
    WidgetRef ref, {
    String? deckId,
    String? deckName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(deckId: deckId, deckName: deckName),
      ),
    );
    ref.invalidate(_dueProvider);
    ref.invalidate(_decksProvider);
  }

  Future<void> _openDeck(
    BuildContext context,
    WidgetRef ref, {
    required String deckId,
    required String deckName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeckDetailScreen(deckId: deckId, deckName: deckName),
      ),
    );
    // Adding or reviewing words inside the deck changes both of these.
    ref.invalidate(_dueProvider);
    ref.invalidate(_decksProvider);
  }

  Future<void> _createDeck(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Шинэ багц'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Нэр',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Болих'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Үүсгэх'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(repositoryProvider).createDeck(name);
      ref.invalidate(_decksProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Үүсгэж чадсангүй: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(_decksProvider);
    final due = ref.watch(_dueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hanko'),
        actions: [
          IconButton(
            icon: const Icon(Icons.local_fire_department_outlined),
            tooltip: 'Статистик',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Шинэ багц',
            onPressed: () => _createDeck(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_decksProvider);
          ref.invalidate(_dueProvider);
        },
        child: ListView(
          children: [
            due.when(
              loading: () => const ListTile(title: Text('…')),
              error: (e, _) => ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: const Text('Өнөөдрийн ачааллыг уншиж чадсангүй'),
                subtitle: Text('$e', style: const TextStyle(fontSize: 11)),
              ),
              data: (d) => Card(
                margin: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        '${d.dueNow}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      subtitle: Text(
                        d.heldBack > 0
                            ? 'Өнөөдөр давтах · өдрийн хязгаараас ${d.heldBack} хойшлов'
                            : 'Өнөөдөр давтах',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Давтах'),
                          onPressed: d.dueNow == 0
                              ? null
                              : () => _startReview(context, ref),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            decks.when(
              loading: () =>
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Багцуудыг уншиж чадсангүй:\n$e'),
              ),
              data: (rows) => Column(
                children: [
                  for (final deck in rows)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(deck['name'] as String? ?? '—'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _openDeck(
                        context,
                        ref,
                        deckId: deck['id'] as String,
                        deckName: deck['name'] as String? ?? '—',
                      ),
                    ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Багц алга.'),
                    ),
                ],
              ),
            ),
            const Divider(),
            const ReminderTile(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
