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
    this.color = HankoColors.seal,
    this.centerText,
  });

  final num pct;
  final String label;
  final double size;
  final double stroke;
  final Color color;
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
              painter: _RingPainter(value / 100, stroke, color, context.hk.sealTint),
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
