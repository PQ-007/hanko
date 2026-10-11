import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/duel/duel_chat_rules.dart';

// Same cases as web/src/app/decks/review/duel/_lib/chat.test.ts.
void main() {
  const them = 'u-them';
  ChatPayload? strangers(Object? p) => acceptIncoming(p, opponentId: them, isFriend: false);
  ChatPayload? friends(Object? p) => acceptIncoming(p, opponentId: them, isFriend: true);

  test('emotes and phrases from the opponent are shown, by known id only', () {
    expect(strangers({'v': 1, 'from': them, 'kind': 'emote', 'id': 'taunt'})?.toJson(),
        {'v': 1, 'from': them, 'kind': 'emote', 'id': 'taunt'});
    expect(strangers({'v': 1, 'from': them, 'kind': 'phrase', 'id': 'gg'})?.id, 'gg');
    expect(strangers({'v': 1, 'from': them, 'kind': 'emote', 'id': 'nuke'}), isNull);
    expect(strangers({'v': 1, 'from': them, 'kind': 'phrase', 'id': '<b>hi</b>'}), isNull);
  });

  test("typed text only between friends — a stranger's never reaches the screen", () {
    expect(strangers({'v': 1, 'from': them, 'kind': 'text', 'text': 'hello'}), isNull);
    expect(friends({'v': 1, 'from': them, 'kind': 'text', 'text': 'hello'})?.text, 'hello');
    expect(friends({'v': 1, 'from': them, 'kind': 'text', 'text': '   '}), isNull);
    expect(friends({'v': 1, 'from': them, 'kind': 'text', 'text': 42}), isNull);
  });

  test('only the opponent, only this protocol version, only objects', () {
    expect(friends({'v': 1, 'from': 'someone-else', 'kind': 'emote', 'id': 'wave'}), isNull);
    expect(friends({'v': 2, 'from': them, 'kind': 'emote', 'id': 'wave'}), isNull);
    expect(friends({'from': them, 'kind': 'emote', 'id': 'wave'}), isNull);
    expect(friends('wave'), isNull);
    expect(friends(null), isNull);
    expect(friends({'v': 1, 'from': them, 'kind': 'emote', 'id': 'wave', 'html': 'x'})!.toJson().keys.toSet(),
        {'v', 'from', 'kind', 'id'});
  });

  test('typed text is cleaned: control and direction characters, whitespace, length', () {
    expect(cleanChatText('  hi\n\tthere  '), 'hi there');
    expect(cleanChatText('a\u202eb\u200bc'), 'a b c');
    expect(cleanChatText('x' * 500).length, maxChatText);
    expect(friends({'v': 1, 'from': them, 'kind': 'text', 'text': 'y' * 500})?.text?.length, maxChatText);
  });

  test('what a message reads as', () {
    expect(chatDisplayText(const ChatPayload(from: them, kind: ChatKind.emote, id: 'rip')), '💀');
    expect(chatDisplayText(const ChatPayload(from: them, kind: ChatKind.phrase, id: 'gg')), 'Сайн тоглолт!');
    expect(chatDisplayText(const ChatPayload(from: them, kind: ChatKind.text, text: 'сайн уу')), 'сайн уу');
  });

  test('an emote plays the first pose the fighter has, else idle', () {
    const full = ['idle', 'walk', 'attack01', 'attack02', 'attack03', 'hurt', 'death', 'block'];
    const archer = ['idle', 'walk', 'attack01', 'attack02', 'hurt', 'death'];
    const bat = ['idle', 'attack01', 'attack02', 'hurt', 'death'];
    expect(emotePose(full, 'taunt'), 'attack03');
    expect(emotePose(archer, 'taunt'), 'attack02');
    expect(emotePose(full, 'guard'), 'block');
    expect(emotePose(archer, 'guard'), 'hurt');
    expect(emotePose(bat, 'wave'), 'idle', reason: 'a bat has no walk');
    expect(emotePose(full, 'unknown'), 'idle');
  });

  test('the ready room starts on two readys, or at the shared deadline', () {
    final started = DateTime.parse('2026-10-11T10:00:00.000Z');
    final deadline = readyDeadline(started, DateTime(2000));
    expect(deadline, started.add(const Duration(milliseconds: readyRoomMs)));
    final now = DateTime(2026);
    expect(readyDeadline(null, now), now.add(const Duration(milliseconds: readyRoomMs)));
    expect(shouldStart(meReady: true, foeReady: true, now: started, deadline: deadline), isTrue);
    expect(
      shouldStart(
        meReady: true,
        foeReady: false,
        now: deadline.subtract(const Duration(milliseconds: 1)),
        deadline: deadline,
      ),
      isFalse,
    );
    expect(shouldStart(meReady: false, foeReady: false, now: deadline, deadline: deadline), isTrue,
        reason: 'nobody can stall it');
  });

  test('rate limit: four in four seconds, then room again as the window slides', () {
    final h = <int>[];
    expect([0, 100, 200, 300].map((t) => allowMessage(h, t)).toList(), [true, true, true, true]);
    expect(allowMessage(h, 3999), isFalse);
    expect(allowMessage(h, 4000), isTrue, reason: 'the first has left the window');
    expect(allowMessage(h, 4001), isFalse);
  });

  test("ready broadcasts: the opponent's, a real boolean, this version", () {
    expect(acceptReady({'v': 1, 'from': them, 'ready': true}, them), isTrue);
    expect(acceptReady({'v': 1, 'from': them, 'ready': false}, them), isFalse);
    expect(acceptReady({'v': 1, 'from': 'someone-else', 'ready': true}, them), isNull);
    expect(acceptReady({'v': 1, 'from': them, 'ready': 'yes'}, them), isNull);
    expect(acceptReady({'v': 2, 'from': them, 'ready': true}, them), isNull);
    expect(acceptReady(null, them), isNull);
  });
}
