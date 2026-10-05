import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import 'ocr_layout.dart';

/// What the photo view hands back: the crop and the brushed units.
typedef PhotoEdit = ({Rect crop, Set<int> brushed});

enum _Mode { crop, select }

/// The photo itself, like a translate app's camera view: crop to the part of
/// the page you want, then brush over words with a finger to pick them.
///
/// Works on copies; returns null when backed out of, so an edit can be
/// abandoned without touching the photo.
class PhotoViewScreen extends StatefulWidget {
  const PhotoViewScreen({super.key, required this.photo});
  final ScannedPhoto photo;

  @override
  State<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<PhotoViewScreen> {
  ui.Image? _image;
  late Rect _crop = widget.photo.crop;
  late final Set<int> _brushed = {...widget.photo.brushed};
  _Mode _mode = _Mode.crop;

  // Drag state.
  _CropDrag? _cropDrag;
  bool _brushValue = true;
  Offset? _lastBrush;

  /// Last layout's mapping between image pixels and the screen.
  _Fit? _fit;

  ScannedPhoto get _photo => widget.photo;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await File(_photo.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Rect get _view => _mode == _Mode.select ? _crop : Offset.zero & _photo.size;

  // ---- Crop ---------------------------------------------------------------

  void _cropStart(Offset screen) {
    final fit = _fit;
    if (fit == null) return;
    const reach = 32.0;
    final corners = {
      _CropDrag.topLeft: _crop.topLeft,
      _CropDrag.topRight: _crop.topRight,
      _CropDrag.bottomLeft: _crop.bottomLeft,
      _CropDrag.bottomRight: _crop.bottomRight,
    };
    _CropDrag? best;
    var bestDist = reach;
    corners.forEach((k, p) {
      final d = (fit.toScreen(p) - screen).distance;
      if (d < bestDist) {
        best = k;
        bestDist = d;
      }
    });
    _cropDrag = best ?? (_crop.contains(fit.toImage(screen)) ? _CropDrag.move : null);
  }

  void _cropUpdate(Offset screenDelta) {
    final fit = _fit;
    final drag = _cropDrag;
    if (fit == null || drag == null) return;
    final d = screenDelta / fit.scale;
    final size = _photo.size;
    final minSide = size.shortestSide * 0.05;
    var r = _crop;
    switch (drag) {
      case _CropDrag.move:
        final dx = d.dx.clamp(-r.left, size.width - r.right);
        final dy = d.dy.clamp(-r.top, size.height - r.bottom);
        r = r.shift(Offset(dx, dy));
      case _CropDrag.topLeft:
        r = Rect.fromLTRB((r.left + d.dx).clamp(0, r.right - minSide), (r.top + d.dy).clamp(0, r.bottom - minSide),
            r.right, r.bottom);
      case _CropDrag.topRight:
        r = Rect.fromLTRB(r.left, (r.top + d.dy).clamp(0, r.bottom - minSide),
            (r.right + d.dx).clamp(r.left + minSide, size.width), r.bottom);
      case _CropDrag.bottomLeft:
        r = Rect.fromLTRB((r.left + d.dx).clamp(0, r.right - minSide), r.top, r.right,
            (r.bottom + d.dy).clamp(r.top + minSide, size.height));
      case _CropDrag.bottomRight:
        r = Rect.fromLTRB(r.left, r.top, (r.right + d.dx).clamp(r.left + minSide, size.width),
            (r.bottom + d.dy).clamp(r.top + minSide, size.height));
    }
    setState(() => _crop = r);
  }

  // ---- Brush --------------------------------------------------------------

  int? _unitAt(Offset screen) {
    final fit = _fit;
    if (fit == null) return null;
    final p = fit.toImage(screen);
    // A few screen pixels of slack: characters are small and fingers aren't.
    final slack = 6 / fit.scale;
    for (var i = 0; i < _photo.units.length; i++) {
      final u = _photo.units[i];
      if (inCrop(u, _crop) && u.rect.inflate(slack).contains(p)) return i;
    }
    return null;
  }

  void _brushStart(Offset screen) {
    final hit = _unitAt(screen);
    // Starting on a picked character unpicks; anywhere else picks.
    _brushValue = hit == null || !_brushed.contains(hit);
    _lastBrush = screen;
    _brushAt(screen);
  }

  void _brushUpdate(Offset screen) {
    // Sample along the stroke so a quick swipe doesn't skip characters.
    final from = _lastBrush ?? screen;
    final steps = ((screen - from).distance / 4).ceil().clamp(1, 200);
    for (var s = 1; s <= steps; s++) {
      _brushAt(Offset.lerp(from, screen, s / steps)!);
    }
    _lastBrush = screen;
  }

  void _brushAt(Offset screen) {
    final hit = _unitAt(screen);
    if (hit == null) return;
    if (_brushValue ? _brushed.add(hit) : _brushed.remove(hit)) setState(() {});
  }

  void _tap(Offset screen) {
    final hit = _unitAt(screen);
    if (hit == null) return;
    setState(() => _brushed.contains(hit) ? _brushed.remove(hit) : _brushed.add(hit));
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final words = pickedWords(_photo.units, _crop, _brushed);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(T.capturePhotoTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: image == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, box) {
                    final fit = _fit = _Fit(_view, box.biggest);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) =>
                          _mode == _Mode.crop ? _cropStart(d.localPosition) : _brushStart(d.localPosition),
                      onPanUpdate: (d) =>
                          _mode == _Mode.crop ? _cropUpdate(d.delta) : _brushUpdate(d.localPosition),
                      onPanEnd: (_) {
                        _cropDrag = null;
                        _lastBrush = null;
                      },
                      onTapUp: _mode == _Mode.select ? (d) => _tap(d.localPosition) : null,
                      child: CustomPaint(
                        size: box.biggest,
                        painter: _PhotoPainter(
                          image: image,
                          fit: fit,
                          crop: _crop,
                          units: _photo.units,
                          brushed: _brushed,
                          selecting: _mode == _Mode.select,
                        ),
                      ),
                    );
                  }),
          ),
          _Panel(
            mode: _mode,
            words: words,
            onMode: (m) => setState(() => _mode = m),
            onClear: _brushed.isEmpty ? null : () => setState(_brushed.clear),
            onDone: () => Navigator.of(context).pop<PhotoEdit>((crop: _crop, brushed: _brushed)),
          ),
        ],
      ),
    );
  }
}

enum _CropDrag { move, topLeft, topRight, bottomLeft, bottomRight }

/// [view] (image pixels) fitted inside [box], centred.
class _Fit {
  _Fit(this.view, Size box) {
    final fitted = applyBoxFit(BoxFit.contain, view.size, box).destination;
    dest = Alignment.center.inscribe(fitted, Offset.zero & box);
    scale = dest.width / view.width;
  }

  final Rect view;
  late final Rect dest;
  late final double scale;

  Offset toScreen(Offset p) => dest.topLeft + (p - view.topLeft) * scale;
  Offset toImage(Offset s) => view.topLeft + (s - dest.topLeft) / scale;
  Rect rectToScreen(Rect r) => Rect.fromPoints(toScreen(r.topLeft), toScreen(r.bottomRight));
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter({
    required this.image,
    required this.fit,
    required this.crop,
    required this.units,
    required this.brushed,
    required this.selecting,
  });

  final ui.Image image;
  final _Fit fit;
  final Rect crop;
  final List<OcrUnit> units;
  final Set<int> brushed;
  final bool selecting;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(fit.dest);
    canvas.drawImageRect(image, fit.view, fit.dest, Paint()..filterQuality = FilterQuality.medium);

    final screenCrop = fit.rectToScreen(crop);
    if (!selecting) {
      // Dim what the crop leaves out.
      canvas.drawPath(
        Path.combine(PathOperation.difference, Path()..addRect(fit.dest), Path()..addRect(screenCrop)),
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
    }

    // Recognised text: a faint outline, so it's clear what can be picked;
    // picked characters filled.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = HankoColors.seal.withValues(alpha: 0.55);
    final picked = Paint()..color = HankoColors.seal.withValues(alpha: 0.45);
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      if (!inCrop(u, crop)) continue;
      final r = fit.rectToScreen(u.rect);
      if (brushed.contains(i)) {
        canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(3)), picked);
      } else if (selecting) {
        canvas.drawRect(r, outline);
      }
    }
    canvas.restore();

    if (!selecting) {
      canvas.drawRect(
        screenCrop,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
      final handle = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white;
      const l = 22.0;
      for (final (c, dx, dy) in [
        (screenCrop.topLeft, 1.0, 1.0),
        (screenCrop.topRight, -1.0, 1.0),
        (screenCrop.bottomLeft, 1.0, -1.0),
        (screenCrop.bottomRight, -1.0, -1.0),
      ]) {
        canvas.drawLine(c, c + Offset(l * dx, 0), handle);
        canvas.drawLine(c, c + Offset(0, l * dy), handle);
      }
    }
  }

  @override
  bool shouldRepaint(_PhotoPainter old) => true;
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.mode,
    required this.words,
    required this.onMode,
    required this.onClear,
    required this.onDone,
  });

  final _Mode mode;
  final List<String> words;

  final ValueChanged<_Mode> onMode;
  final VoidCallback? onClear;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.hk.card,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(value: _Mode.crop, icon: Icon(Icons.crop), label: Text(T.captureModeCrop)),
                  ButtonSegment(value: _Mode.select, icon: Icon(Icons.brush_outlined), label: Text(T.captureModeSelect)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => onMode(s.single),
              ),
              const SizedBox(height: 8),
              Text(
                '${mode == _Mode.crop ? T.captureCropHint : T.captureSelectHint} ${T.captureAutoHint}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.hk.inkMute),
              ),
              if (words.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Scrolls sideways rather than growing over the photo.
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final w in words)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Chip(label: Text(w), visualDensity: VisualDensity.compact),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onClear != null) ...[
                    OutlinedButton(onPressed: onClear, child: const Text(T.captureClear)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onDone,
                      icon: const Icon(Icons.check),
                      label: Text(words.isEmpty ? T.captureDone : T.captureDoneN(words.length)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
