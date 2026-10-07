import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/library.dart';
import '../share/story_sheet.dart';
import '../share/story_sources.dart';

/// A deck's public link, the same one the web makes (`set_deck_share`, 0028):
/// anyone with it sees the deck's words and plays a trial in the browser, no
/// account needed. It expires 24 hours after it's made; your name and review
/// history are never shown.
Future<void> showDeckShareSheet(BuildContext context, Deck deck) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DeckShareSheet(deck: deck),
    );

class _DeckShareSheet extends ConsumerStatefulWidget {
  const _DeckShareSheet({required this.deck});
  final Deck deck;

  @override
  ConsumerState<_DeckShareSheet> createState() => _DeckShareSheetState();
}

class _DeckShareSheetState extends ConsumerState<_DeckShareSheet> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  String? _token;
  DateTime? _expires;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // Keeps the "time left" honest while the sheet is open.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await _db.from('decks').select('share_token, share_expires_at').eq('id', widget.deck.id).single();
      _apply(row['share_token'] as String?, row['share_expires_at'] as String?);
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _apply(String? token, String? expires) {
    _token = token;
    _expires = expires == null ? null : DateTime.parse(expires).toLocal();
  }

  bool get _live => _token != null && _expires != null && _expires!.isAfter(DateTime.now());
  String get _link => '${Config.webUrl}/share/$_token';

  Future<void> _set(bool on) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final r = await _db.rpc('set_deck_share', params: {'p_deck_id': widget.deck.id, 'p_on': on});
      final m = Map<String, dynamic>.from(r as Map);
      _apply(m['token'] as String?, m['expires_at'] as String?);
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final left = _live ? _expires!.difference(DateTime.now()) : Duration.zero;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(T.shareDeckTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(T.shareDeckDesc, style: TextStyle(color: hk.inkSoft)),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_live) ...[
            Row(
              children: [
                Icon(Icons.link, size: 18, color: context.hk.sealText),
                const SizedBox(width: 6),
                Text(T.shareLinkOn, style: TextStyle(fontWeight: FontWeight.w600, color: context.hk.sealText)),
                const Spacer(),
                Text(T.shareTimeLeft(left), style: TextStyle(fontSize: 12, color: hk.inkMute)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: hk.paperDim, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(_link, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text(T.shareCopy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _link));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(T.shareCopied)));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text(T.shareSend),
                    onPressed: () => SharePlus.instance.share(ShareParams(text: '${widget.deck.name}\n$_link')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _set(false),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: const Text(T.shareLinkDisable),
            ),
            Text(T.shareLinkDisableHint, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: hk.inkMute)),
          ] else
            FilledButton.icon(
              icon: const Icon(Icons.link),
              label: const Text(T.shareLinkEnable),
              onPressed: _busy ? null : () => _set(true),
            ),
          const SizedBox(height: 12),
          Divider(color: hk.lineSoft),
          const SizedBox(height: 4),
          // A story image of the deck — works with or without the link on.
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text(T.shareStoryImage),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: () => showStorySheet(
              context,
              title: T.shareStoryImage,
              card: deckStory(widget.deck),
              fileName: 'deck-story',
              emptyText: T.noWords,
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: 10),
            Text(T.shareFailed, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
