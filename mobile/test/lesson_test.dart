import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/writing/kanji_strokes.dart';
import 'package:mobile/features/writing/lesson.dart';

void main() {
  group('planLesson', () {
    test('a new kanji climbs the ladder, then the word is asked whole', () {
      expect(planLesson(['連帯']).map((s) => '$s'), [
        'trace:連', 'partial:連', 'blank:連',
        'trace:帯', 'partial:帯', 'blank:帯',
        'word#0',
      ]);
    });

    test('kana in a word are given, only its kanji are taught', () {
      expect(planLesson(['食べる']).map((s) => '$s'), ['trace:食', 'partial:食', 'blank:食', 'word#0']);
    });

    test('a kanji already learned goes straight to its word', () {
      expect(planLesson(['連帯'], learned: {'連'}).map((s) => '$s'),
          ['trace:帯', 'partial:帯', 'blank:帯', 'word#0']);
      expect(planLesson(['連帯'], learned: {'連', '帯'}).map((s) => '$s'), ['word#0']);
    });

    test('a kanji taught earlier in the lesson is not taught again', () {
      expect(planLesson(['連帯', '連中']).map((s) => '$s'), [
        'trace:連', 'partial:連', 'blank:連', 'trace:帯', 'partial:帯', 'blank:帯', 'word#0',
        'trace:中', 'partial:中', 'blank:中', 'word#1',
      ]);
    });

    test('a single-kanji word just taught is not asked twice', () {
      expect(planLesson(['猫']).map((s) => '$s'), ['trace:猫', 'partial:猫', 'blank:猫']);
      expect(planLesson(['猫'], learned: {'猫'}).map((s) => '$s'), ['word#0'], reason: 'review');
    });

    test('kana-only words contribute nothing', () {
      expect(planLesson(['ありがとう']), isEmpty);
    });
  });

  test('the word step asks for kanji positions only', () {
    expect(kanjiPositions('食べ物'), [0, 2]);
    expect(kanjiOf('時々'), ['時', '々']);
  });

  test('the partial step shows the first half of the strokes', () {
    expect(partialStrokes(9), 4);
    expect(partialStrokes(2), 1);
    expect(partialStrokes(1), 0);
  });

  test('words with new kanji come first', () {
    expect(newKanjiFirst(['猫', '連帯', '犬'], (w) => w, {'猫', '犬'}), ['連帯', '猫', '犬']);
  });

  test('KanjiVG: strokes in order, nothing but strokes (食 has 9)', () {
    final svg = File('test/fixtures/kanjivg_098df.svg').readAsStringSync();
    final strokes = parseKanjiVg(svg);
    expect(strokes, hasLength(9));
    expect(strokes.first, startsWith('M52.75,10.5'));
    expect(kanjiVgFile('食'), '098df.svg');
    final k = KanjiStrokes('食', strokes);
    expect(k.starts.first.dx, 52.75);
    for (final p in k.paths) {
      final b = p.getBounds();
      expect(b.left >= 0 && b.right <= KanjiStrokes.box && b.top >= 0 && b.bottom <= KanjiStrokes.box, isTrue,
          reason: 'every stroke inside the 109 box');
    }
  });

  test('the kanji grid: each kanji once, in the order the words have them', () {
    expect(kanjiInOrder(['連帯', '連中', '食べる']), ['連', '帯', '中', '食']);
  });

  test('picked kanji map to the first word that has them, without doubling up', () {
    final words = ['連帯', '連中', '中心', '食べる'];
    expect(wordsForKanji(['連', '帯'], words, (w) => w), ['連帯'], reason: 'one word covers both');
    expect(wordsForKanji(['中', '食'], words, (w) => w), ['連中', '食べる']);
    expect(wordsForKanji(['猫'], words, (w) => w), isEmpty);
  });

  // Same cases as lesson.test.ts (web).
  group('lessonSize', () {
    const pairs = ['学校', '先生', '電車', '会社', '時間', '新聞'];

    test('stops before passing 10 new kanji', () {
      expect(lessonSize(pairs, 0), 5); // 5 × 2 = 10; the 6th would make 12
      expect(lessonSize(pairs, 5), 1); // the rest is the next lesson
    });

    test("kanji already learned don't count", () {
      expect(lessonSize(pairs, 0, learned: {'学', '校', '先', '生'}), 6);
    });

    test('a kanji repeated across words counts once', () {
      expect(lessonSize(['学校', '学生', '校長'], 0), 3);
    });

    test('one word over the cap still gets a lesson', () {
      expect(lessonSize(['一二三四五六七八九十百', '学校'], 0), 1);
    });

    test('at most 10 words even when nothing is new', () {
      final terms = List.filled(12, '学校');
      expect(lessonSize(terms, 0, learned: {'学', '校'}), 10);
      expect(lessonSize(const [], 0), 0);
    });
  });
}
