import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/share/story_card.dart';

// Same cases as web/src/app/decks/_lib/storyCard.test.ts, so the two
// wrapLines can't drift. One unit per character: width 10 = ten characters.
double m(String s) => s.runes.length.toDouble();

void main() {
  test('short text stays on one line', () {
    expect(wrapLines(m, 'идэх', 10, 2), ['идэх']);
  });

  test('breaks at spaces and keeps every word when it fits', () {
    expect(wrapLines(m, 'нууц, маш нууц мэдээлэл', 10, 3), ['нууц, маш', 'нууц', 'мэдээлэл']);
  });

  test('too long for the lines allowed: the last line ends in an ellipsis', () {
    final lines = wrapLines(m, 'нууц, маш нууц мэдээлэл, далд', 10, 2);
    expect(lines.length, 2);
    expect(lines[0], 'нууц, маш');
    expect(lines[1].endsWith('…'), isTrue);
    expect(m(lines[1]) <= 10, isTrue);
  });

  test('a single word longer than a line is split inside the word', () {
    expect(wrapLines(m, 'агааржуулалтынхан', 10, 2), ['агааржуула', 'лтынхан']);
    final cut = wrapLines(m, 'агааржуулалтынхантай холбоотой', 10, 2);
    expect(cut.length, 2);
    expect(cut[1].endsWith('…'), isTrue);
  });

  test('empty text gives no lines', () {
    expect(wrapLines(m, '   ', 10, 2), isEmpty);
  });

  test('story size follows the screen shape, clamped', () {
    expect(storySize(const ui.Size(360, 800)), const ui.Size(1080, 2400));
    expect(storySize(const ui.Size(800, 400)), const ui.Size(1080, 2340));
    expect(storySize(const ui.Size(300, 1000)).height, (1080 * 22 / 9).roundToDouble());
  });

  testWidgets('renders a PNG of the right size in every style and language', (tester) async {
    const card = StoryCard(
      kicker: '10-р сарын 7',
      heading: 'Өнөөдөр сурсан үгс',
      numbers: [StoryNumber('15', 'үг санасан'), StoryNumber('5', 'шинэ үг')],
      words: [
        StoryWord(term: '機密', reading: 'きみつ', meaningMn: 'нууц', meaningEn: 'secret'),
        StoryWord(term: '等', reading: 'など', meaningMn: 'гэх мэт', meaningEn: 'et cetera'),
      ],
      total: 15,
    );
    await tester.runAsync(() async {
      for (final s in StoryStyle.values) {
        for (final l in StoryLang.values) {
          final png = await renderStoryCard(card, const ui.Size(1080, 2340), s, l);
          final codec = await ui.instantiateImageCodec(png);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 1080);
          expect(frame.image.height, 2340);
          frame.image.dispose();
        }
      }
    });
  });

}
