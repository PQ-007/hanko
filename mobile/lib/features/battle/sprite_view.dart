import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sprites.dart';

/// Decoded sprite sheets, shared across every SpriteView. A sheet is a few KB;
/// keeping them decoded means a pose change paints immediately instead of
/// flashing an empty box while the PNG decodes (the web preloads for the same
/// reason, FighterSprite.tsx).
class SpriteSheets {
  SpriteSheets._();

  static final _cache = <String, Future<ui.Image>>{};

  static String path(String slug, String state) =>
      'assets/battle/characters/$slug/$state.png';

  static Future<ui.Image> load(String slug, String state) => loadAsset(path(slug, state));

  static Future<ui.Image> loadAsset(String key) {
    return _cache.putIfAbsent(key, () async {
      final data = await rootBundle.load(key);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    });
  }

  /// Warm the clips a character can reach, so its first attack isn't blank.
  static void preload(String slug, [Iterable<String>? states]) {
    final meta = spriteFrames[slug];
    if (meta == null) return;
    for (final s in states ?? meta.keys) {
      if (meta.containsKey(s)) unawaited(load(slug, s));
    }
  }
}

/// One animated fighter. [size] is the on-screen size of the 100px source
/// frame. Loops (idle, walk) repeat; one-shots (attacks, hurt, death) play once
/// and HOLD their last real frame — the jump-none rule from the web's
/// globals.css, which exists because ending one step past the sheet painted a
/// blank frame at the end of every hit.
///
/// Changing [state] restarts the clip from frame 0, even if it's the same
/// state again — two crits in a row must both swing. Bump [replayKey] for that.
class SpriteView extends StatefulWidget {
  const SpriteView({
    super.key,
    required this.slug,
    this.state = 'idle',
    this.size = 100,
    this.flip = false,
    this.replayKey = 0,
    this.onOneShotEnd,
  });

  final String slug;
  final String state;
  final double size;
  final bool flip;
  final int replayKey;
  final VoidCallback? onOneShotEnd;

  @override
  State<SpriteView> createState() => _SpriteViewState();
}

class _SpriteViewState extends State<SpriteView>
    with SingleTickerProviderStateMixin {
  // Created in initState, not lazily: a sprite removed before its sheet has
  // loaded would otherwise first touch the controller inside dispose(), which
  // builds it against a deactivated element and throws. The loading scene
  // swaps fighters every few seconds, so that happened routinely.
  late final AnimationController _clock;
  ui.Image? _sheet;
  String _resolved = 'idle';
  int _frames = 1;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this)..addStatusListener(_onStatus);
    SpriteSheets.preload(widget.slug);
    _start();
  }

  @override
  void didUpdateWidget(SpriteView old) {
    super.didUpdateWidget(old);
    if (old.slug != widget.slug) SpriteSheets.preload(widget.slug);
    if (old.slug != widget.slug ||
        old.state != widget.state ||
        old.replayKey != widget.replayKey) {
      _start();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !isLoopState(_resolved)) {
      widget.onOneShotEnd?.call();
    }
  }

  Future<void> _start() async {
    final token = ++_loadToken;
    final resolved = resolveState(widget.slug, widget.state);
    final frames = framesOf(widget.slug, widget.state);
    final loop = isLoopState(resolved);

    final sheet = await SpriteSheets.load(widget.slug, resolved);
    if (!mounted || token != _loadToken) return;

    setState(() {
      _sheet = sheet;
      _resolved = resolved;
      _frames = frames;
    });
    _clock
      ..stop()
      ..duration = Duration(milliseconds: loop ? loopMs : oneShotMs)
      ..value = 0;
    if (frames <= 1) return;
    if (loop) {
      _clock.repeat();
    } else {
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return SizedBox.square(
      dimension: widget.size,
      child: sheet == null
          ? null
          : AnimatedBuilder(
              animation: _clock,
              builder: (_, _) => CustomPaint(
                painter: _FramePainter(
                  sheet: sheet,
                  // steps(F, jump-none): F stops across [0, 1] inclusive, so
                  // t = 1 lands on the last real frame and holds it.
                  frame: (_clock.value * _frames).floor().clamp(0, _frames - 1),
                  offset: spriteOffsets[widget.slug] ?? (x: 0, y: 0),
                  flip: widget.flip,
                ),
              ),
            ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.sheet,
    required this.frame,
    required this.offset,
    required this.flip,
  });

  final ui.Image sheet;
  final int frame;
  final ({int x, int y}) offset;
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    // The box this widget is given spans [visibleFrame] frame pixels, not the
    // full 100. Source frames are sized for each character's widest attack,
    // so a standing figure fills only a small middle patch of the frame —
    // sized to the whole frame, every character looked tiny. Same trick as the web's
    // .hanko-fighter-slot (68 units): size the box to the body, and let swings
    // and projectiles paint past it, unclipped.
    final scale = size.width / visibleFrame;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    // Same order as FighterSprite.tsx: mirror, scale, then nudge the
    // character to the centre of its own frame — so the nudge grows with the
    // sprite and flips with it.
    if (flip) canvas.scale(-1, 1);
    canvas.scale(scale);
    canvas.translate(offset.x - 50.0, offset.y - 50.0);
    canvas.drawImageRect(
      sheet,
      Rect.fromLTWH(frame * 100.0, 0, 100, 100),
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  /// Frame pixels the widget's box covers. Measured on the actual sheets
  /// (first idle frame, trimmed): a standing character is only ~17-26 px wide
  /// and ~14-32 px tall inside its 100px frame — knight 26x21, wizard 17x21,
  /// black-knight-a 17x32 (the tallest). SPRITE_OFFSET centres that content,
  /// so 36 fits the tallest idle with a little air and makes every character
  /// ~2.8x larger than drawing the whole frame.
  static const visibleFrame = 36.0;

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame ||
      old.sheet != sheet ||
      old.flip != flip ||
      old.offset != offset;
}


/// A projectile in flight (projectiles.ts / ProjectileShot.tsx): an arrow,
/// bolt or orb crossing from thrower to target. Drawn at the same frame scale
/// as a fighter of [fighterSize], so ammunition matches the hand that threw
/// it. Multi-frame shots churn while they fly; the parent moves it.
class ProjectileView extends StatefulWidget {
  const ProjectileView({
    super.key,
    required this.slug,
    required this.pose,
    required this.frames,
    required this.fighterSize,
    this.flip = false,
  });

  final String slug;
  final String pose;
  final int frames;
  final double fighterSize;

  /// The art points right; a monster's shot is the same sheet mirrored.
  final bool flip;

  @override
  State<ProjectileView> createState() => _ProjectileViewState();
}

class _ProjectileViewState extends State<ProjectileView> with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  ui.Image? _sheet;

  @override
  void initState() {
    super.initState();
    // Loops several times over a short flight (frames x 45ms, as on the web).
    _clock = AnimationController(vsync: this, duration: Duration(milliseconds: widget.frames * 45));
    if (widget.frames > 1) _clock.repeat();
    SpriteSheets.loadAsset('assets/battle/projectiles/${widget.slug}/${widget.pose}.png').then((img) {
      if (mounted) setState(() => _sheet = img);
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (sheet == null) return SizedBox.square(dimension: widget.fighterSize);
    return SizedBox.square(
      dimension: widget.fighterSize,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (_, _) => CustomPaint(
          painter: _FramePainter(
            sheet: sheet,
            frame: (_clock.value * widget.frames).floor().clamp(0, widget.frames - 1),
            offset: (x: 0, y: 0),
            flip: widget.flip,
          ),
        ),
      ),
    );
  }
}
