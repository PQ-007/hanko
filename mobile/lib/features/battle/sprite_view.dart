import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

  /// Folders (one per character or projectile) whose sheets are cached, least
  /// recently used first. Every sheet decoded is 72 MB, and the loading scene
  /// draws a random pair each round, so an unbounded cache crept toward all
  /// of it — and Android kills a big app first when memory runs low. A screen
  /// shows at most a hero, a monster and their shots, so ten folders is
  /// plenty. Evicting only drops the cache's reference: a sprite still
  /// showing keeps its image.
  static final _recent = <String>[];
  static const _maxFolders = 10;

  static String path(String slug, String state) =>
      'assets/battle/characters/$slug/$state.png';

  static Future<ui.Image> load(String slug, String state) => loadAsset(path(slug, state));

  static Future<ui.Image> loadAsset(String key) {
    _touch(key.substring(0, key.lastIndexOf('/') + 1));
    return _cache.putIfAbsent(key, () async {
      try {
        final data = await rootBundle.load(key);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        return (await codec.getNextFrame()).image;
      } catch (_) {
        _cache.remove(key); // let a later call retry
        rethrow;
      }
    });
  }

  static void _touch(String folder) {
    if (_recent.isNotEmpty && _recent.last == folder) return;
    _recent
      ..remove(folder)
      ..add(folder);
    while (_recent.length > _maxFolders) {
      final old = _recent.removeAt(0);
      _cache.removeWhere((k, _) => k.startsWith(old));
    }
  }

  /// Warm the clips a character can reach, so its first attack isn't blank.
  static void preload(String slug, [Iterable<String>? states]) {
    final meta = spriteFrames[slug];
    if (meta == null) return;
    for (final s in states ?? meta.keys) {
      if (meta.containsKey(s)) load(slug, s).ignore();
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

/// Steps frames on a timer, not an AnimationController. A clip shows a new
/// frame every ~100-150 ms, but a controller drives a full build/paint/raster
/// pass on every vsync (90-120 Hz) for as long as a sprite is on screen — the
/// home hero and the loading fight never stop, so the app never idled. Now a
/// frame is drawn only when the picture changes.
///
/// Timing matches the controller it replaces: each of F frames holds clipMs/F;
/// a one-shot reaches its last frame at (F-1)/F, holds it, and ends (calling
/// [SpriteView.onOneShotEnd]) at clipMs. Paused while TickerMode is off
/// (offstage routes, hidden tabs), as a controller's ticker would be.
class _SpriteViewState extends State<SpriteView> {
  final _frame = ValueNotifier<int>(0);
  Timer? _timer;
  ValueListenable<TickerModeData>? _tickerMode;
  ui.Image? _sheet;
  int _frames = 1;
  bool _loop = true;
  bool _ended = false;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    SpriteSheets.preload(widget.slug);
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_schedule);
      _tickerMode = mode..addListener(_schedule);
      _schedule();
    }
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

  Future<void> _start() async {
    final token = ++_loadToken;
    final resolved = resolveState(widget.slug, widget.state);
    final frames = framesOf(widget.slug, widget.state);

    final ui.Image sheet;
    try {
      sheet = await SpriteSheets.load(widget.slug, resolved);
    } catch (_) {
      return; // missing or undecodable sheet: draw nothing rather than throw
    }
    if (!mounted || token != _loadToken) return;

    setState(() {
      _sheet = sheet;
      _frames = frames;
    });
    _loop = isLoopState(resolved);
    _ended = false;
    _frame.value = 0;
    _timer?.cancel();
    _timer = null;
    _schedule();
  }

  /// Runs the frame timer while there's a clip to play and tickers are on.
  void _schedule() {
    final run = _sheet != null && _frames > 1 && !_ended && (_tickerMode?.value.enabled ?? true);
    if (!run) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    final stepMs = (_loop ? loopMs : oneShotMs) / _frames;
    _timer = Timer.periodic(Duration(microseconds: (stepMs * 1000).round()), (_) => _step());
  }

  void _step() {
    final next = _frame.value + 1;
    if (_loop) {
      _frame.value = next % _frames;
    } else if (next < _frames) {
      _frame.value = next;
    } else {
      // Past the last frame: hold it and end the clip.
      _ended = true;
      _schedule();
      widget.onOneShotEnd?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tickerMode?.removeListener(_schedule);
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return SizedBox.square(
      dimension: widget.size,
      child: sheet == null
          ? null
          : CustomPaint(
              painter: _FramePainter(
                sheet: sheet,
                frame: _frame,
                offset: spriteOffsets[widget.slug] ?? (x: 0, y: 0),
                flip: widget.flip,
              ),
            ),
    );
  }
}

/// Draws one frame of a sheet. [frame] is either a plain int or a listenable
/// that repaints the sprite (and only the sprite — no rebuild) on change.
class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.sheet,
    required Object frame,
    required this.offset,
    required this.flip,
  })  : _frame = frame,
        super(repaint: frame is Listenable ? frame : null);

  final ui.Image sheet;
  final Object _frame;
  final ({int x, int y}) offset;
  final bool flip;

  int get frame => switch (_frame) {
        ValueListenable<int> l => l.value,
        int i => i,
        _ => 0,
      };

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
      old._frame != _frame ||
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
    }).ignore();
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
