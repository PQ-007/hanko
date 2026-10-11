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
          for (final layout in StoryLayout.values) {
            final png = await renderStoryCard(card, const ui.Size(1080, 2340), s, l, layout: layout, seed: 1);
            final codec = await ui.instantiateImageCodec(png);
            final frame = await codec.getNextFrame();
            expect(frame.image.width, 1080);
            expect(frame.image.height, 2340);
            frame.image.dispose();
          }
        }
      }
    });
  });


  // buildStoryQuiz — the same cases as storyCard.test.ts (web).
  group('buildStoryQuiz', () {
    StoryWord w(String term, String? mn, [String? en]) => StoryWord(term: term, meaningMn: mn, meaningEn: en);
    final five = [w('a', 'm1', 'e1'), w('b', 'm2', 'e2'), w('c', 'm3', 'e3'), w('d', 'm4', 'e4'), w('e', 'm5', 'e5')];

    test('word, options and answer slot follow the seed', () {
      final q0 = buildStoryQuiz(five, StoryLang.mn, 0)!;
      expect(q0.word, same(five[0]));
      expect(q0.options, ['m2', 'm1', 'm3', 'm4']);
      expect(q0.answer, 1);
      final q6 = buildStoryQuiz(five, StoryLang.mn, 6)!;
      expect(q6.word, same(five[1]));
      expect(q6.options, ['m3', 'm4', 'm5', 'm2']);
      expect(q6.answer, 3);
    });

    test('English options when English is asked; Mongolian falls back to English', () {
      expect(buildStoryQuiz(five, StoryLang.en, 0)!.options, ['e2', 'e1', 'e3', 'e4']);
      final mixed = [w('a', null, 'e1'), w('b', 'm2'), w('c', 'm3'), w('d', 'm4')];
      expect(buildStoryQuiz(mixed, StoryLang.mn, 0)!.options, ['m2', 'e1', 'm3', 'm4']);
    });

    test('a repeated meaning is never offered twice', () {
      final dup = [w('a', 'x'), w('b', 'x'), w('c', 'y'), w('d', 'z'), w('e', 'v')];
      expect(buildStoryQuiz(dup, StoryLang.mn, 0)!.options, ['y', 'x', 'z', 'v']);
    });

    test('null without four words of distinct meaning', () {
      expect(buildStoryQuiz(five.sublist(0, 3), StoryLang.mn, 0), isNull);
      expect(buildStoryQuiz([w('a', 'x'), w('b', 'x'), w('c', 'x'), w('d', 'y'), w('e', 'z')], StoryLang.mn, 0), isNull);
      expect(buildStoryQuiz([w('a', ''), w('b', 'm2'), w('c', 'm3'), w('d', 'm4')], StoryLang.mn, 0), isNull);
    });
  });

  testWidgets('the mascot loads with its figure measured, and every layout draws with it', (tester) async {
    await tester.runAsync(() async {
      final art = await loadStoryArt('knight');
      expect(art.idle, isNotNull);
      expect(art.cheer, isNotNull);
      // The figure is much smaller than its 100×100 frame — that's why it's measured.
      expect(art.idleBox!.height, lessThan(80));
      expect(art.idleBox!.width, greaterThan(5));
      expect(art.cheerFrame, greaterThan(0));

      final none = await loadStoryArt('no-such-hero');
      expect(none.idle, isNull, reason: 'a missing asset just means no mascot');

      const card = StoryCard(
        kicker: '10-р сарын 9',
        heading: 'Өнөөдөр сурсан үгс',
        numbers: [StoryNumber('15', 'үг санасан'), StoryNumber('5', 'шинэ үг'), StoryNumber('6', 'өдөр дараалан')],
        words: [
          StoryWord(term: '機密', reading: 'きみつ', meaningMn: 'нууц'),
          StoryWord(term: '等', reading: 'など', meaningMn: 'гэх мэт'),
          StoryWord(term: '把握', reading: 'はあく', meaningMn: 'атгах'),
          StoryWord(term: '居住', reading: 'きょじゅう', meaningMn: 'оршин суух'),
        ],
        week: [StoryDay('Да', false), StoryDay('Мя', true), StoryDay('Лх', true)],
        bubble: '6 өдөр дараалан!',
      );
      for (final layout in StoryLayout.values) {
        final png = await renderStoryCard(card, const ui.Size(1080, 1920), StoryStyle.paper, StoryLang.mn,
            layout: layout, art: art, says: 'Сайн уу!');
        expect(png.length, greaterThan(1000));
      }
    });
  });
}
