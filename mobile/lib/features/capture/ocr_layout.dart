import 'dart:ui';

import 'segment.dart';

/// The smallest piece of recognised text the photo view works with: one
/// character where ML Kit reports characters (it does for Japanese), else one
/// element. Kept free of ML Kit types so the crop and brush rules can be
/// tested without a device.
class OcrUnit {
  const OcrUnit({required this.line, required this.text, required this.rect, this.gapBefore = false});

  /// Index of the line this unit belongs to, in reading order.
  final int line;
  final String text;

  /// In image pixels.
  final Rect rect;

  /// A visible gap separates this unit from the previous one on its line —
  /// the space between 連帯 and れんたい in a vocabulary list. Brushed words
  /// and line text both break here.
  final bool gapBefore;
}

/// One photographed page: its recognised text and what the user did with it.
class ScannedPhoto {
  ScannedPhoto({required this.path, required this.size, required this.units, Rect? crop})
      : crop = crop ?? defaultCrop(units, size);

  final String path;
  final Size size;
  final List<OcrUnit> units;

  /// Only text inside this counts. Starts as the area the text covers, so the
  /// desk around a page is already gone.
  Rect crop;

  /// Indexes into [units] brushed on the photo.
  final Set<int> brushed = {};

  /// The words this photo last put on the chosen list, so a later edit can
  /// take back the ones it no longer picks.
  List<String> picked = const [];
}

/// What a photo picks: every suggested word inside the crop, plus anything
/// brushed. Suggestions come pre-selected because a photographed word list
/// is mostly words you want — unticking a few beats tapping dozens. Brushing
/// adds what suggestions can't find (hiragana-only words, odd splits).
List<String> pickedWords(List<OcrUnit> units, Rect crop, Set<int> brushed) {
  final words = [...suggestWords(linesIn(units, crop))];
  for (final w in brushedWords(units, brushed)) {
    if (!words.contains(w)) words.add(w);
  }
  return words;
}

/// Units whose centres fall inside [crop].
bool inCrop(OcrUnit u, Rect crop) => crop.contains(u.rect.center);

/// The text inside [crop], one string per line, gaps kept as spaces.
List<String> linesIn(List<OcrUnit> units, Rect crop) {
  final lines = <int, StringBuffer>{};
  for (final u in units) {
    if (!inCrop(u, crop)) continue;
    final b = lines.putIfAbsent(u.line, StringBuffer.new);
    if (b.isNotEmpty && u.gapBefore) b.write(' ');
    b.write(u.text);
  }
  final keys = lines.keys.toList()..sort();
  return [for (final k in keys) lines[k].toString()];
}

/// Words made from brushed units: each unbroken run on one line is a word. A
/// run breaks at an unbrushed unit, at a visible gap, and at a line end.
List<String> brushedWords(List<OcrUnit> units, Set<int> brushed) {
  final words = <String>[];
  final current = StringBuffer();
  void end() {
    final w = current.toString().trim();
    if (w.isNotEmpty && !words.contains(w)) words.add(w);
    current.clear();
  }

  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    final newLine = i == 0 || units[i - 1].line != u.line;
    if (newLine || u.gapBefore || !brushed.contains(i)) end();
    if (brushed.contains(i)) current.write(u.text);
  }
  end();
  return words;
}

/// The area the text covers plus a margin, clamped to the image.
Rect defaultCrop(List<OcrUnit> units, Size size) {
  final full = Offset.zero & size;
  if (units.isEmpty) return full;
  var r = units.first.rect;
  for (final u in units.skip(1)) {
    r = r.expandToInclude(u.rect);
  }
  return r.inflate(size.shortestSide * 0.02).intersect(full);
}

/// Whether two neighbouring boxes on a line are separated by a visible gap:
/// wider than half the line's height, so the normal spacing between
/// characters doesn't count but the column gap in a word list does.
bool isGap(Rect previous, Rect next, double lineHeight) =>
    next.left - previous.right > lineHeight * 0.5;
