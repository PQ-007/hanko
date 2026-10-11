import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'duel_chat_rules.dart';

class ChatEntry {
  const ChatEntry({required this.key, required this.mine, required this.kind, required this.text});
  final int key;
  final bool mine;
  final ChatKind kind;
  final String text;
}

/// The latest thing a side said or did, for its fighter's bubble and pose.
class ChatBeat {
  const ChatBeat({required this.nonce, required this.text, this.emote});
  final int nonce;
  final String text;
  final String? emote;
}

/// One Realtime channel per match, alive from the ready room to the result
/// screen — the mobile side of the web's useDuelChat.ts, on the same channel
/// and events, so a phone and a browser talk to each other.
///
/// The wire shape is the web's: `{type, event, payload: {...}}`. supabase-js
/// sends that from `channel.send({..., payload})`, but realtime_client's
/// sendBroadcastMessage puts its map at the top level, so this wraps the
/// message in `payload` itself, and reads `payload` back out (falling back to
/// the top level for a flat sender).
class DuelChat extends ChangeNotifier {
  DuelChat({
    required SupabaseClient db,
    required this.matchId,
    required this.meId,
    required this.opponentId,
    required this.isFriend,
  }) {
    final ch = db.channel(
      chatTopic(matchId),
      opts: RealtimeChannelConfig(key: meId),
    );
    _channel = ch;
    _db = db;
    ch
        .onBroadcast(
          event: chatEvent,
          callback: (m) {
            final p = acceptIncoming(_inner(m), opponentId: opponentId, isFriend: isFriend);
            if (p == null || !allowMessage(_received, _nowMs)) return;
            _push(p, mine: false);
          },
        )
        .onBroadcast(
          event: readyEvent,
          callback: (m) {
            final r = acceptReady(_inner(m), opponentId);
            if (r == null) return;
            foeReady = r;
            foePresent = true;
            _notify();
          },
        )
        .onPresenceSync((_) {
          final theirs = [
            for (final s in ch.presenceState())
              for (final p in s.presences)
                if (p.payload['user'] == opponentId) p.payload,
          ];
          foePresent = theirs.isNotEmpty;
          foeReady = theirs.any((p) => p['ready'] == true);
          _notify();
        })
        .subscribe((status, _) {
          _subscribed = status == RealtimeSubscribeStatus.subscribed;
          if (_subscribed) ch.track({'user': meId, 'ready': meReady});
        });
  }

  final String matchId, meId, opponentId;
  final bool isFriend;
  late final SupabaseClient _db;
  late final RealtimeChannel _channel;
  bool _subscribed = false;
  bool _disposed = false;

  final entries = <ChatEntry>[];
  ChatBeat? mine;
  ChatBeat? foe;
  bool meReady = false;
  bool foeReady = false;
  bool foePresent = false;
  bool get canType => isFriend;

  final _sent = <int>[];
  final _received = <int>[];
  int _nonce = 0;

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  static Object? _inner(Map<String, dynamic> m) => m['payload'] is Map ? m['payload'] : m;

  void _push(ChatPayload p, {required bool mine}) {
    final text = chatDisplayText(p);
    if (text.isEmpty) return;
    final key = ++_nonce;
    entries.add(ChatEntry(key: key, mine: mine, kind: p.kind, text: text));
    // A match's worth of chat, not an archive.
    if (entries.length > 40) entries.removeAt(0);
    final beat = ChatBeat(nonce: key, text: text, emote: p.kind == ChatKind.emote ? p.id : null);
    if (mine) {
      this.mine = beat;
    } else {
      foe = beat;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Sends an emote id, a phrase id, or (friends only) text. False when it
  /// wasn't sent — empty, not allowed, or too many too fast.
  bool send(ChatKind kind, String value) {
    if (kind == ChatKind.text && !isFriend) return false;
    final payload = kind == ChatKind.text
        ? ChatPayload(from: meId, kind: kind, text: cleanChatText(value))
        : ChatPayload(from: meId, kind: kind, id: value);
    if (kind == ChatKind.text && (payload.text ?? '').isEmpty) return false;
    if (!allowMessage(_sent, _nowMs)) return false;
    _push(payload, mine: true);
    _channel.sendBroadcastMessage(event: chatEvent, payload: {'payload': payload.toJson()});
    return true;
  }

  void setReady(bool value) {
    meReady = value;
    _notify();
    if (!_subscribed) return;
    _channel.sendBroadcastMessage(
      event: readyEvent,
      payload: {
        'payload': {'v': 1, 'from': meId, 'ready': value},
      },
    );
    _channel.track({'user': meId, 'ready': value});
  }

  @override
  void dispose() {
    _disposed = true;
    _db.removeChannel(_channel);
    super.dispose();
  }
}
