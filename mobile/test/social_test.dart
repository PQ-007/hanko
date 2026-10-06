import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/social/social_api.dart';

void main() {
  test('levels: each costs a little more than the last', () {
    expect(levelFor(0), 1);
    expect(levelFor(99), 1);
    expect(levelFor(100), 2);
    expect(levelFor(1600), 5);
    expect(levelFor(8100), 10);
    for (var lv = 1; lv < 30; lv++) {
      expect(levelFor(xpForLevel(lv)), lv, reason: 'level $lv starts where xpForLevel says');
      expect(levelFor(xpForLevel(lv + 1) - 1), lv);
    }
  });

  test('friend_overview rows parse, hidden numbers stay null', () {
    final hidden = FriendRow.fromJson({'user_id': 'u', 'handle': 'bat', 'name': null, 'image': null, 'is_me': false, 'shares': false});
    expect(hidden.xpTotal, isNull);
    expect(hidden.displayName, 'bat');
    final me = FriendRow.fromJson({
      'user_id': 'm', 'handle': 'anu', 'name': 'Anu', 'is_me': true, 'shares': true,
      'elo': 1016, 'xp_total': 59, 'recent_kanji': ['連', '帯'],
    });
    expect(me.recentKanji, ['連', '帯']);
    expect(me.elo, 1016);
  });
}
