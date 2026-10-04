import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'sprite_view.dart';
import 'sprites.dart';

/// A looping fight: two characters walk on, trade blows, one goes down, and a
/// new pair walks on. Port of the web's FightScene.tsx, used here as the
/// app's loading state in place of a spinner.
///
/// Decoration only: it owns no data, and whatever mounts it decides when it
/// goes away.
class FightScene extends StatefulWidget {
  const FightScene({super.key, this.hero, this.size = 96, this.label, this.heroWins = false});

  /// Fixed fighter, or null to draw a new hero with each pair.
  final String? hero;
  final double size;
  final String? label;

  /// When the hero is the viewer's own character, they shouldn't watch
  /// themselves lose.
  final bool heroWins;

  @override
  State<FightScene> createState() => _FightSceneState();
}

const _walk = Duration(milliseconds: 1300);
const _clash = Duration(milliseconds: oneShotMs + 40);
const _finish = Duration(milliseconds: 1100);
const _exchanges = 4;
const _sceneClips = ['walk', 'attack01', 'attack02', 'attack03', 'hurt', 'death'];

class _FightSceneState extends State<FightScene> with SingleTickerProviderStateMixin {
  final _random = Random();
  late final AnimationController _walkIn =
      AnimationController(vsync: this, duration: _walk);
  Timer? _timer;

  late String _hero;
  late String _monster;
  int _blow = 0;
  int _round = 0;

  // Phase: approach (blow 0), clash (1..exchanges), finish (exchanges+1).
  String _attacker = 'hero';
  String _pose = 'attack01';
  String _loser = 'monster';

  @override
  void initState() {
    super.initState();
    _newPair();
    _walkIn.forward(from: 0);
    _timer = Timer(_walk, _advance);
  }

  void _newPair() {
    _hero = widget.hero ?? playerRoster[_random.nextInt(playerRoster.length)];
    _monster = monsterBag.pick(exclude: _hero);
    SpriteSheets.preload(_hero, _sceneClips);
    SpriteSheets.preload(_monster, _sceneClips);
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      _blow += 1;
      if (_blow <= _exchanges) {
        _attacker = _blow.isOdd ? 'hero' : 'monster';
        final slug = _attacker == 'hero' ? _hero : _monster;
        // Every third blow is the heaviest clip, so the exchange escalates.
        _pose = _blow % 3 == 0 ? critPose(slug) : 'attack01';
        _timer = Timer(_clash, _advance);
      } else if (_blow == _exchanges + 1) {
        _loser = widget.heroWins || _random.nextBool() ? 'monster' : 'hero';
        _pose = critPose(_loser == 'hero' ? _monster : _hero);
        _timer = Timer(_finish, _advance);
      } else {
        _newPair();
        _blow = 0;
        _round += 1;
        _walkIn.forward(from: 0);
        _timer = Timer(_walk, _advance);
      }
    });
  }

  String _poseOf(String who) {
    if (_blow == 0) return 'walk';
    if (_blow > _exchanges) return _loser == who ? 'death' : _pose;
    return _attacker == who ? _pose : 'hurt';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _walkIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hero = widget.hero ?? _hero;
    final curve = CurvedAnimation(parent: _walkIn, curve: Curves.easeOut);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: curve,
          builder: (context, _) {
            final t = curve.value;
            return Opacity(
              opacity: (t * 5).clamp(0, 1).toDouble(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: Offset(-56 * (1 - t), 0),
                    child: SpriteView(
                      key: ValueKey('hero$_round'),
                      slug: hero,
                      state: _poseOf('hero'),
                      replayKey: _blow,
                      size: widget.size,
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(56 * (1 - t), 0),
                    child: SpriteView(
                      key: ValueKey('monster$_round'),
                      slug: _monster,
                      state: _poseOf('monster'),
                      replayKey: _blow,
                      size: widget.size,
                      flip: true,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.label!,
            style: const TextStyle(fontSize: 13, color: HankoColors.inkSoft),
          ),
        ],
      ],
    );
  }
}

/// The app's loading state: a fight, centred, with a caption.
class LoadingScene extends StatelessWidget {
  const LoadingScene({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: FightScene(label: label),
      ),
    );
  }
}

/// Empty state with the viewer's hero idling beside a message.
class HeroEmptyState extends StatelessWidget {
  const HeroEmptyState({
    super.key,
    required this.hero,
    required this.title,
    this.subtitle,
    this.action,
    this.state = 'idle',
  });

  final String hero;
  final String title;
  final String? subtitle;
  final Widget? action;
  final String state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpriteView(slug: hero, state: state, size: 120),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: HankoColors.inkSoft),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
