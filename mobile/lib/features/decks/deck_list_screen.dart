import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository.dart';
import '../../models/queue_card.dart';

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
    });
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
                child: ListTile(
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
                    ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Багц алга.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
