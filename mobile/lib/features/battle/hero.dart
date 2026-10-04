import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sprites.dart';

/// Same key name as the web's localStorage entry (playerCharacter.ts). Kept
/// per device rather than on the profile: it changes nothing server-side, and
/// a round trip before the arena's first frame would buy nothing.
const _key = 'hanko.battle.character';

final heroProvider = NotifierProvider<HeroNotifier, String>(HeroNotifier.new);

class HeroNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return defaultPlayerCharacter;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      // Validated against the roster, not trusted: a slug left behind by a
      // rename would otherwise draw an empty fighter for a whole session.
      if (stored != null && playerRoster.contains(stored)) state = stored;
    } catch (_) {
      // Keep the default.
    }
  }

  Future<void> choose(String slug) async {
    if (!playerRoster.contains(slug)) return;
    state = slug;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, slug);
    } catch (_) {
      // A choice that doesn't survive a restart is a small loss.
    }
  }
}
