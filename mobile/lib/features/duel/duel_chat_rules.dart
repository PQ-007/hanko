// Duel chat rules — a port of web/src/app/decks/review/duel/_lib/chat.ts,
// pinned by the same cases (duel_chat_rules_test.dart / chat.test.ts), so a
// phone and a browser in one match agree on what gets shown.
//
// Nothing is stored: messages go over a Realtime broadcast on the match's
// channel, which makes the RECEIVER the one that enforces the rules — only the
// opponent's messages, only known emote/phrase ids, and typed text only when
// duel_opponent() said the two of you are friends.

const chatEvent = 'msg';

/// "Ready" goes out on this event as well as in presence: presence takes 2-3 s
/// to reach the other side, which started one player's first round that much
/// before the other's (chat.ts READY_EVENT).
const readyEvent = 'ready';

String chatTopic(String matchId) => 'duel-chat:$matchId';

/// How long the ready room waits for two "ready"s before starting anyway.
const readyRoomMs = 30000;

/// Typed messages are cut to this.
const maxChatText = 120;

/// At most this many messages in [rateWindowMs], sent or shown.
const rateMax = 4;
const rateWindowMs = 4000;

class Emote {
  const Emote(this.id, this.icon, this.poses);
  final String id;
  final String icon;

  /// The first of these the character has plays on the sender's fighter.
  final List<String> poses;
}

const emotes = [
  Emote('wave', '👋', ['walk']),
  Emote('taunt', '😤', ['attack03', 'attack02', 'attack01']),
  Emote('cheer', '🎉', ['attack01']),
  Emote('ouch', '😵', ['hurt']),
  Emote('guard', '🛡️', ['block', 'hurt']),
  Emote('rip', '💀', ['death']),
];

const phrases = <String, String>{
  'hi': 'Сайн уу!',
  'gl': 'Амжилт хүсье!',
  'gg': 'Сайн тоглолт!',
  'wow': 'Гоё байна!',
  'close': 'Арай л гэж!',
  'again': 'Дахиад нэг үү?',
  'thanks': 'Баярлалаа!',
};

enum ChatKind { emote, phrase, text }

class ChatPayload {
  const ChatPayload({required this.from, required this.kind, this.id, this.text});
  final String from;
  final ChatKind kind;
  final String? id;
  final String? text;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'from': from,
    'kind': kind.name,
    'id': ?id,
    'text': ?text,
  };
}

final _controls = RegExp('[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]');

/// Whitespace collapsed, control and direction characters gone, cut to
/// [maxChatText].
String cleanChatText(String s) {
  var t = s.replaceAll(_controls, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length > maxChatText) t = t.substring(0, maxChatText);
  return t.trim();
}

/// The incoming message to show, or null.
ChatPayload? acceptIncoming(Object? payload, {required String opponentId, required bool isFriend}) {
  if (payload is! Map) return null;
  if (payload['v'] != 1 || payload['from'] != opponentId) return null;
  final id = payload['id'];
  switch (payload['kind']) {
    case 'emote':
      return emotes.any((e) => e.id == id)
          ? ChatPayload(from: opponentId, kind: ChatKind.emote, id: id as String)
          : null;
    case 'phrase':
      return phrases.containsKey(id) ? ChatPayload(from: opponentId, kind: ChatKind.phrase, id: id as String) : null;
    case 'text':
      final raw = payload['text'];
      if (!isFriend || raw is! String) return null;
      final text = cleanChatText(raw);
      return text.isEmpty ? null : ChatPayload(from: opponentId, kind: ChatKind.text, text: text);
    default:
      return null;
  }
}

/// The opponent's ready flag from a [readyEvent] broadcast, or null.
bool? acceptReady(Object? payload, String opponentId) {
  if (payload is! Map) return null;
  if (payload['v'] != 1 || payload['from'] != opponentId) return null;
  final r = payload['ready'];
  return r is bool ? r : null;
}

/// What a message reads as in the log and the speech bubble.
String chatDisplayText(ChatPayload p) => switch (p.kind) {
  ChatKind.emote => emotes.where((e) => e.id == p.id).firstOrNull?.icon ?? '',
  ChatKind.phrase => phrases[p.id] ?? '',
  ChatKind.text => p.text ?? '',
};

/// The pose an emote plays on a fighter that has the clips in [available].
String emotePose(Iterable<String> available, String emote) {
  final e = emotes.where((x) => x.id == emote).firstOrNull;
  return e?.poses.where(available.contains).firstOrNull ?? 'idle';
}

/// When the ready room starts on its own: 30 s after the server marked the
/// match active (matches.started_at), the same moment on both screens.
DateTime readyDeadline(DateTime? startedAt, DateTime now) =>
    (startedAt ?? now).add(const Duration(milliseconds: readyRoomMs));

bool shouldStart({required bool meReady, required bool foeReady, required DateTime now, required DateTime deadline}) =>
    (meReady && foeReady) || !now.isBefore(deadline);

/// Sliding-window rate limit: true (and the time recorded) when another
/// message fits.
bool allowMessage(List<int> history, int nowMs) {
  while (history.isNotEmpty && nowMs - history.first >= rateWindowMs) {
    history.removeAt(0);
  }
  if (history.length >= rateMax) return false;
  history.add(nowMs);
  return true;
}
