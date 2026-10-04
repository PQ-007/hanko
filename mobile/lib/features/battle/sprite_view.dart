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

  static Future<ui.Image> load(String slug, String state) {
    final key = path(slug, state);
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
  late final AnimationController _clock = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  ui.Image? _sheet;
  String _resolved = 'idle';
  int _frames = 1;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
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
    final scale = size.width / 100;
    canvas.save();
    // Same order as FighterSprite.tsx: mirror, scale, then nudge the
    // character to the centre of its own frame — so the nudge grows with the
    // sprite and flips with it.
    if (flip) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.scale(scale);
    canvas.translate(offset.x.toDouble(), offset.y.toDouble());
    canvas.drawImageRect(
      sheet,
      Rect.fromLTWH(frame * 100.0, 0, 100, 100),
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame ||
      old.sheet != sheet ||
      old.flip != flip ||
      old.offset != offset;
}
