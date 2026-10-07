import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Radial meter (web ProgressRing.tsx). [pct] (0–100) drives the arc; the
/// centre shows the percentage unless [centerText] is given, for rings whose
/// value isn't itself a percentage ("7/20").
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.pct,
    required this.label,
    this.size = 96,
    this.stroke = 9,
    this.color,
    this.centerText,
  });

  final num pct;
  final String label;
  final double size;
  final double stroke;
  /// Defaults to the theme's accent.
  final Color? color;
  final String? centerText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: pct.clamp(0, 100).toDouble()),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _RingPainter(value / 100, stroke, color ?? context.hk.seal, context.hk.sealTint),
              child: Center(
                child: Text(
                  centerText ?? '${value.round()}%',
                  style: TextStyle(
                    fontSize: centerText == null ? size * 0.22 : size * 0.19,
                    fontWeight: FontWeight.w700,
                    color: context.hk.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: context.hk.inkSoft)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.stroke, this.color, this.track);
  final double fraction;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arcRect, 0, 2 * pi, false, trackPaint);
    if (fraction <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -pi / 2, 2 * pi * fraction, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.stroke != stroke || old.track != track;
}

/// Space to leave under a session's answer buttons so they sit where the
/// thumb rests while holding the phone, not against the bottom edge (or the
/// gesture bar). Scales with screen height: ~80px on a typical 6.5" phone.
double thumbZoneLift(BuildContext context) =>
    MediaQuery.sizeOf(context).height * 0.09;

/// Section card with a small title row, the dashboard's building block.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.trailing, required this.child});
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap rather than Row: the Mongolian summaries ("Сүүлийн хагас
            // жилд 785 давталт · 120 өдөр") are long, and on a phone a Row
            // overflowed past the card's edge. Wrapped, the summary simply
            // drops under the title when there isn't room beside it.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: context.hk.inkSoft)),
                if (trailing != null)
                  Text(trailing!, style: TextStyle(fontSize: 11, color: context.hk.inkMute)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Hanko's mark — the open ensō from the app icon and the web favicon,
/// painted (no asset) so it stays crisp at any size. Same path as the web's
/// "practice" icon: an 8-unit circle on a 24 grid, left open at the top right.
class EnsoMark extends StatelessWidget {
  const EnsoMark({super.key, this.size = 28, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _EnsoPainter(color));
}

class _EnsoPainter extends CustomPainter {
  _EnsoPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final path = Path()
      ..moveTo(17.6 * s, 5.6 * s)
      ..arcToPoint(Offset(20 * s, 11.2 * s), radius: Radius.circular(8 * s), largeArc: true, clockwise: false);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * s
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(_EnsoPainter old) => old.color != color;
}

/// A person's picture — their uploaded or Google photo (https only), else the
/// first letter of their name on the seal tint. Used for you (home, settings)
/// and for friends, so everyone looks the same everywhere.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.image, this.radius = 20});
  final String name;
  final String? image;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final img = image;
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.hk.sealTint,
      foregroundImage: img != null && img.startsWith('https://') ? NetworkImage(img) : null,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: context.hk.sealText, fontWeight: FontWeight.w800, fontSize: radius * 0.8),
      ),
    );
  }
}
