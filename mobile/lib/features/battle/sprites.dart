import 'dart:math';

import 'sprite_data.dart';

export 'sprite_data.dart';

// Pose resolution and monster drawing, ported from the web's sprites.ts and
// monsters.ts. The data tables live in sprite_data.dart, generated from the
// shared fixture; only the rules are written by hand here.

/// The pose a character can actually play: falls back to idle for a clip it
/// doesn't ship (most have no `block`). Every character has idle.
String resolveState(String slug, String state) {
  final meta = spriteFrames[slug];
  if (meta == null) return 'idle';
  return meta.containsKey(state) ? state : 'idle';
}

int framesOf(String slug, String state) =>
    spriteFrames[slug]?[resolveState(slug, state)] ?? 1;

bool isLoopState(String state) => state == 'idle' || state == 'walk';

/// A character's attacks lightest to heaviest, filtered to what it ships.
List<String> attackChain(String slug) {
  final meta = spriteFrames[slug];
  final chain = [
    for (final s in const ['attack01', 'attack02', 'attack03'])
      if (meta != null && meta.containsKey(s)) s,
  ];
  return chain.isEmpty ? const ['attack01'] : chain;
}

const maxAttackTier = 2;

/// Escalation, clamped: a character with two attacks tops out on its second
/// rather than losing the swing at tier 2.
String attackPose(String slug, int tier) {
  final chain = attackChain(slug);
  return chain[tier.clamp(0, chain.length - 1)];
}

String critPose(String slug) => attackPose(slug, maxAttackTier);

/// Shuffle-bag monster draw (monsters.ts): every monster appears once before
/// any appears twice, nothing repeats back to back, and the player's own
/// character is never drawn as the opponent.
class MonsterBag {
  MonsterBag({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<String> _bag = [];
  String? _last;

  void _refill() {
    _bag
      ..clear()
      ..addAll(monsterRoster);
    for (var i = _bag.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final t = _bag[i];
      _bag[i] = _bag[j];
      _bag[j] = t;
    }
    if (_bag.length > 1 && _bag.last == _last) {
      final t = _bag.last;
      _bag[_bag.length - 1] = _bag[0];
      _bag[0] = t;
    }
  }

  String pick({String? exclude}) {
    if (_bag.isEmpty) _refill();
    var i = _bag.length - 1;
    if (exclude != null) {
      while (i >= 0 && _bag[i] == exclude) {
        i--;
      }
      if (i < 0) {
        _refill();
        i = _bag.length - 1;
        while (i >= 0 && _bag[i] == exclude) {
          i--;
        }
      }
      if (i < 0) i = _bag.length - 1;
    }
    final next = _bag.removeAt(i);
    _last = next;
    return next;
  }
}

/// One bag for the whole app, like the web's module-level bag: the loading
/// scene and the arena draw from the same cycle.
final monsterBag = MonsterBag();
