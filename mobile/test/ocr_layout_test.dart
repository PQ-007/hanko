import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/capture/ocr_layout.dart';

/// Lays a string out as 10px characters on [line]; a space becomes a gap.
List<OcrUnit> row(int line, String text, {double y = 0}) {
  final out = <OcrUnit>[];
  var x = 0.0;
  var gap = false;
  for (final ch in text.split('')) {
    if (ch == ' ') {
      x += 20;
      gap = true;
      continue;
    }
    out.add(OcrUnit(line: line, text: ch, rect: Rect.fromLTWH(x, y + line * 20.0, 10, 10), gapBefore: gap));
    x += 10;
    gap = false;
  }
  return out;
}

void main() {
  final page = [...row(0, '連帯 れんたい'), ...row(1, '路地 ろじ'), ...row(2, '廊下 ろうか')];

  test('the crop keeps only the text inside it', () {
    expect(linesIn(page, const Rect.fromLTWH(0, 0, 500, 500)), ['連帯 れんたい', '路地 ろじ', '廊下 ろうか']);
    // Left column only, first two lines.
    expect(linesIn(page, const Rect.fromLTWH(0, 0, 25, 35)), ['連帯', '路地']);
  });

  test('a brushed run is one word; a gap or a new line starts another', () {
    // 連帯 + れん on line 0 (the gap splits them), 路地 on line 1.
    final brushed = {0, 1, 2, 3, 6, 7};
    expect(brushedWords(page, brushed), ['連帯', 'れん', '路地']);
  });

  test('an unbrushed character in the middle splits the run', () {
    expect(brushedWords(page, {2, 4}), ['れ', 'た']);
  });

  test('the same word brushed twice is listed once', () {
    final twice = [...row(0, '連帯'), ...row(1, '連帯')];
    expect(brushedWords(twice, {0, 1, 2, 3}), ['連帯']);
  });

  test('the default crop hugs the text with a margin, inside the image', () {
    final crop = defaultCrop(page, const Size(1000, 1000));
    expect(crop.left, 0, reason: 'clamped to the image');
    expect(crop.contains(page.last.rect.center), isTrue);
    expect(crop.right, lessThan(200), reason: 'not the whole photo');
    expect(defaultCrop(const [], const Size(10, 20)), const Rect.fromLTWH(0, 0, 10, 20));
  });

  test('a gap is wider than half the line height', () {
    const a = Rect.fromLTWH(0, 0, 10, 10);
    expect(isGap(a, const Rect.fromLTWH(12, 0, 10, 10), 10), isFalse);
    expect(isGap(a, const Rect.fromLTWH(30, 0, 10, 10), 10), isTrue);
  });

  test('every suggestion in the crop is picked; brushing adds to it', () {
    const all = Rect.fromLTWH(0, 0, 500, 500);
    expect(pickedWords(page, all, {}), ['連帯', '路地', '廊下'], reason: 'kanji words, not the readings');
    expect(pickedWords(page, const Rect.fromLTWH(0, 0, 500, 15), {}), ['連帯'], reason: 'only inside the crop');
    expect(pickedWords(page, all, {2, 3, 4, 5}), ['連帯', '路地', '廊下', 'れんたい'],
        reason: 'a brushed reading joins the suggestions');
  });
}
