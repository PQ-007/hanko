import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

// A full-screen, unbranded story image (Instagram / Facebook stories) drawn on
// the phone — a port of web/src/app/decks/_lib/storyCard.ts, same layout,
// same three styles, same numbers. Two uses: "today's words" from Home, and a
// shared deck's invitation from the deck share sheet.
//
// Layout: a header (kicker, a headline that may take two lines, up to three
// big numbers), then the words as a two-column grid of cards that grows to
// fill the screen, then a "+N" pill.

class StoryWord {
  const StoryWord({required this.term, this.reading, this.meaningMn, this.meaningEn});
  final String term;
  final String? reading;
  final String? meaningMn;
  final String? meaningEn;
}

enum StoryStyle { seal, dark, paper }

enum StoryLang { mn, en, both }

class StoryNumber {
  const StoryNumber(this.value, this.label);
  final String value;
  final String label;
}

class StoryCard {
  const StoryCard({
    required this.kicker,
    required this.heading,
    this.numbers = const [],
    required this.words,
    this.total,
    this.moreLabel,
  });

  /// Small line over the heading, e.g. the date or "shared deck".
  final String kicker;
  final String heading;

  /// Big numbers under the heading. At most three are drawn.
  final List<StoryNumber> numbers;
  final List<StoryWord> words;

  /// How many words there are in all; the rest show as "+N" after the grid.
  final int? total;
  final String Function(int n)? moreLabel;
}

const storyWidth = 1080;

/// Most words a card ever shows (fewer when the screen is short).
const storyMaxWords = 12;

/// The image size for this phone: 1080 wide, as tall as the screen's own
/// shape (a 1080×2400 phone gets 1080×2400). Landscape or odd shapes get a
/// typical phone, 19.5:9, clamped between 16:9 and 22:9 like the web.
ui.Size storySize(ui.Size screen) {
  var ratio = 2340 / 1080;
  if (screen.width > 0 && screen.height > screen.width) ratio = screen.height / screen.width;
  ratio = ratio.clamp(16 / 9, 22 / 9);
  return ui.Size(storyWidth.toDouble(), (storyWidth * ratio).roundToDouble());
}

class _Palette {
  const _Palette({
    required this.bgTop,
    required this.bgBottom,
    this.bandTop,
    this.bandBottom,
    required this.bandText,
    required this.bandSoft,
    required this.card,
    required this.cardLine,
    required this.term,
    required this.reading,
    required this.meaning,
    required this.accent,
    required this.pill,
    required this.pillText,
    required this.decoRing,
    required this.deco,
    required this.shadow,
  });
  final Color bgTop, bgBottom;
  final Color? bandTop, bandBottom;
  final Color bandText, bandSoft, card, cardLine, term, reading, meaning, accent, pill, pillText;
  final bool decoRing;
  final Color deco, shadow;
}

// Same values as PALETTES in storyCard.ts. Each style is one continuous
// surface; only "dark" keeps a header band.
const _palettes = {
  StoryStyle.seal: _Palette(
    bgTop: Color(0xFF2C72CC),
    bgBottom: Color(0xFF0F3672),
    bandText: Color(0xFFFFFFFF),
    bandSoft: Color(0xB8FFFFFF),
    card: Color(0x1CFFFFFF),
    cardLine: Color(0x33FFFFFF),
    term: Color(0xFFFFFFFF),
    reading: Color(0xB8D6E6FC),
    meaning: Color(0xF0FFFFFF),
    accent: Color(0xFF9FC6F7),
    pill: Color(0xFFFFFFFF),
    pillText: Color(0xFF184F95),
    decoRing: false,
    deco: Color(0x12FFFFFF),
    shadow: Color(0x4D041430),
  ),
  StoryStyle.dark: _Palette(
    bgTop: Color(0xFF14181E),
    bgBottom: Color(0xFF14181E),
    bandTop: Color(0xFF0F1216),
    bandBottom: Color(0xFF1B2129),
    bandText: Color(0xFFF3F1EC),
    bandSoft: Color(0xB3F3F1EC),
    card: Color(0xFF1F252E),
    cardLine: Color(0x0FFFFFFF),
    term: Color(0xFFF3F1EC),
    reading: Color(0xFF9AA3AE),
    meaning: Color(0xFFD4D0C8),
    accent: Color(0xFF6FA3E6),
    pill: Color(0xFF2F6BB8),
    pillText: Color(0xFFFFFFFF),
    decoRing: false,
    deco: Color(0x0FFFFFFF),
    shadow: Color(0x1A000000),
  ),
  StoryStyle.paper: _Palette(
    bgTop: Color(0xFFF8F2E6),
    bgBottom: Color(0xFFEEE2CC),
    bandText: Color(0xFF1F2933),
    bandSoft: Color(0xFFB8402C),
    card: Color(0xFFFFFDF8),
    cardLine: Color(0x21785A32),
    term: Color(0xFF1C232B),
    reading: Color(0xFF8C7F6C),
    meaning: Color(0xFF363D46),
    accent: Color(0xFFC8442F),
    pill: Color(0xFFC8442F),
    pillText: Color(0xFFFFFAF2),
    decoRing: true,
    deco: Color(0x1AC8442F),
    shadow: Color(0x296E5028),
  ),
};

/// Up to [maxLines] lines that fit [width] (as [measure] reports it),
/// breaking at spaces — or inside a word that's longer than a whole line. If
/// text is left over, the last line ends in "…". A port of `wrapLines` in
/// storyCard.ts, pinned by the same cases (story_card_test.dart).
List<String> wrapLines(double Function(String) measure, String text, double width, int maxLines) {
  final tokens = text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final lines = <String>[];
  var cur = '';
  var i = 0;
  var truncated = false;
  while (i < tokens.length) {
    final w = tokens[i];
    final next = cur.isEmpty ? w : '$cur $w';
    if (measure(next) <= width) {
      cur = next;
      i++;
      continue;
    }
    if (cur.isNotEmpty) {
      lines.add(cur);
      cur = '';
      if (lines.length == maxLines) {
        truncated = true;
        break;
      }
      continue;
    }
    // A single word wider than the line: take as many characters as fit.
    final chars = w.runes.map(String.fromCharCode).toList();
    var part = '';
    var j = 0;
    while (j < chars.length && measure(part + chars[j]) <= width) {
      part += chars[j++];
    }
    if (part.isEmpty) part = chars[j++];
    lines.add(part);
    final rest = chars.sublist(j).join();
    if (rest.isNotEmpty) {
      tokens[i] = rest;
    } else {
      i++;
    }
    if (lines.length == maxLines) {
      truncated = i < tokens.length;
      break;
    }
  }
  if (cur.isNotEmpty) {
    if (lines.length < maxLines) {
      lines.add(cur);
    } else {
      truncated = true;
    }
  }
  if (truncated && lines.isNotEmpty) {
    var last = lines.last;
    while (last.length > 1 && measure('$last…') > width) {
      last = last.substring(0, last.length - 1);
    }
    lines[lines.length - 1] = '${last.replaceAll(RegExp(r'[\s,;·]+$'), '')}…';
  }
  return lines;
}

List<String> _meaningsOf(StoryWord w, StoryLang lang) {
  String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
  final mn = clean(w.meaningMn), en = clean(w.meaningEn);
  return switch (lang) {
    StoryLang.mn => [?(mn ?? en)],
    StoryLang.en => [?(en ?? mn)],
    StoryLang.both => [?mn, ?en],
  };
}

/// Text on a canvas the way a 2D context draws it: positioned by its
/// alphabetic baseline, measured by its advance width.
class _Ink {
  _Ink(this.canvas);
  final Canvas canvas;

  TextPainter _painter(String text, double size, FontWeight weight, Color color) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.0),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  double width(String text, double size, FontWeight weight) =>
      _painter(text, size, weight, const Color(0xFF000000)).width;

  /// Draws [text] with its baseline at [y]; [align] 0 = left edge at x,
  /// 0.5 = centred on x.
  void draw(String text, double x, double y, double size, FontWeight weight, Color color,
      {double align = 0}) {
    final p = _painter(text, size, weight, color);
    final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    p.paint(canvas, Offset(x - p.width * align, y - base));
  }

  /// The largest size ≤ max at which text fits in width (never below min).
  double fit(String text, FontWeight weight, double max, double min, double w) {
    var size = max;
    while (size > min && width(text, size, weight) > w) {
      size -= 2;
    }
    return size;
  }

  /// Cut with an ellipsis once text no longer fits.
  String clip(String text, double size, FontWeight weight, double w) {
    if (width(text, size, weight) <= w) return text;
    var t = text;
    while (t.length > 1 && width('$t…', size, weight) > w) {
      t = t.substring(0, t.length - 1);
    }
    return '$t…';
  }
}

RRect _rr(double x, double y, double w, double h, double r) =>
    RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

void drawStoryCard(Canvas canvas, ui.Size size, StoryCard card, StoryStyle style, StoryLang lang) {
  final W = size.width, H = size.height;
  const M = 72.0;
  final p = _palettes[style]!;
  final ink = _Ink(canvas);

  canvas.drawRect(
    Rect.fromLTWH(0, 0, W, H),
    Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, H), [p.bgTop, p.bgBottom]),
  );

  // ---- Header ----
  final headLines = wrapLines((s) => ink.width(s, 92, FontWeight.w800), card.heading, W - 2 * M, 2);
  final numbers = card.numbers.take(3).toList();
  final bandH = 190 + 40 + headLines.length * 104 + (numbers.isNotEmpty ? 200 : 0) + 30.0;
  if (p.bandTop != null && p.bandBottom != null) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W, bandH),
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(W, bandH), [p.bandTop!, p.bandBottom!]),
    );
  }
  // Decoration in the corner — depth without a logo. The ring is open at the
  // bottom-left, like a brushed ensō.
  if (!p.decoRing) {
    final paint = Paint()..color = p.deco;
    canvas.drawCircle(Offset(W - 40, 120), 300, paint);
    canvas.drawCircle(Offset(-60, H - 160), 260, paint);
  } else {
    canvas.drawArc(
      Rect.fromCircle(center: Offset(W - 80, 210), radius: 250),
      math.pi * 0.85,
      math.pi * 1.75,
      false,
      Paint()
        ..color = p.deco
        ..style = PaintingStyle.stroke
        ..strokeWidth = 46
        ..strokeCap = StrokeCap.round,
    );
  }

  var y = 190.0;
  ink.draw(ink.clip(card.kicker.toUpperCase(), 34, FontWeight.w700, W - 2 * M), M, y, 34,
      FontWeight.w700, p.bandSoft);
  y += 40;
  for (final line in headLines) {
    y += 104;
    ink.draw(line, M, y, 92, FontWeight.w800, p.bandText);
  }
  if (numbers.isNotEmpty) {
    y += 60;
    final colW = (W - 2 * M) / numbers.length;
    for (final (i, n) in numbers.indexed) {
      final x = M + i * colW;
      final vs = ink.fit(n.value, FontWeight.w800, 96, 56, colW - 24);
      ink.draw(n.value, x, y + 82, vs, FontWeight.w800, p.bandText);
      ink.draw(ink.clip(n.label, 30, FontWeight.w600, colW - 24), x, y + 130, 30, FontWeight.w600,
          p.bandSoft);
    }
  }
  if (p.bandTop == null) {
    canvas.drawRect(Rect.fromLTWH(M, bandH + 4, W - 2 * M, 2), Paint()..color = p.cardLine);
  }

  // ---- Word grid ----
  final top = bandH + 56;
  final bottom = H - 70;
  const gap = 24.0;
  final colW = (W - 2 * M - gap) / 2;
  // Tall enough for term + reading + a two-line meaning: fewer, readable
  // tiles beat many truncated ones — the rest go in the "+N" pill.
  const minTile = 300.0, maxTile = 380.0, moreH = 110.0;
  final total = card.total ?? card.words.length;
  final roomRows = math.max(1, ((bottom - top - moreH + gap) / (minTile + gap)).floor());
  final words = card.words.take(math.min(storyMaxWords, roomRows * 2)).toList();
  final rows = (words.length / 2).ceil();
  final more = math.max(0, total - words.length);
  final tileH = math.min(
    maxTile,
    (bottom - top - (more > 0 ? moreH : 0) - (rows - 1) * gap) / math.max(rows, 1),
  );
  final gridH = rows * tileH + (rows - 1) * gap;
  // A short grid sits a little lower rather than hugging the header.
  var gy = top + math.max(0, (bottom - top - gridH - (more > 0 ? moreH : 0)) / 4);

  for (final (i, w) in words.indexed) {
    final x = M + (i % 2) * (colW + gap);
    final ty = gy + (i ~/ 2) * (tileH + gap);
    final tile = _rr(x, ty, colW, tileH, 30);
    canvas.drawRRect(
      tile.shift(const Offset(0, 8)),
      Paint()
        ..color = p.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
    canvas.drawRRect(tile, Paint()..color = p.card);
    canvas.drawRRect(
      tile,
      Paint()
        ..color = p.cardLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Accent tick, top-left.
    canvas.drawRRect(_rr(x + 34, ty + 34, 44, 8, 4), Paint()..color = p.accent);

    const pad = 34.0;
    final inner = colW - 2 * pad;
    var ly = ty + 34 + 22;
    final ts = ink.fit(w.term, FontWeight.w800, 72, 40, inner);
    ly += ts;
    ink.draw(ink.clip(w.term, ts, FontWeight.w800, inner), x + pad, ly, ts, FontWeight.w800, p.term);
    final reading = (w.reading != null && w.reading!.isNotEmpty && w.reading != w.term) ? w.reading! : '';
    if (reading.isNotEmpty) {
      ly += 44;
      ink.draw(ink.clip(reading, 30, FontWeight.w500, inner), x + pad, ly, 30, FontWeight.w500, p.reading);
    }
    final meanings = _meaningsOf(w, lang);
    if (meanings.isNotEmpty) {
      ly += 14;
      // Lines left in the tile, shared out: the first meaning gets up to two,
      // the second (English, when both are shown) what's left, up to two.
      var room = math.max(1, ((ty + tileH - 30 - ly) / 40).floor());
      for (final (mi, m) in meanings.indexed) {
        if (room <= 0) break;
        final sz = mi == 0 ? 32.0 : 28.0;
        final wt = mi == 0 ? FontWeight.w600 : FontWeight.w500;
        final take = math.min(2, mi == 0 && meanings.length == 2 && room <= 2 ? 1 : room);
        for (final line in wrapLines((s) => ink.width(s, sz, wt), m, inner, take)) {
          ly += 40;
          ink.draw(line, x + pad, ly, sz, wt, mi == 0 ? p.meaning : p.reading);
          room--;
        }
      }
    }
  }

  gy += gridH;
  if (more > 0) {
    final label = (card.moreLabel ?? (n) => '+$n')(more);
    final pw = ink.width(label, 40, FontWeight.w800) + 80;
    canvas.drawRRect(_rr((W - pw) / 2, gy + 34, pw, 72, 36), Paint()..color = p.pill);
    ink.draw(label, W / 2, gy + 84, 40, FontWeight.w800, p.pillText, align: 0.5);
  }
}

/// The card as PNG bytes.
Future<Uint8List> renderStoryCard(StoryCard card, ui.Size size, StoryStyle style, StoryLang lang) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  drawStoryCard(canvas, size, card, style, lang);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
