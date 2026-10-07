import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/audio/mp3.dart';

void main() {
  // Real clips from Google's TTS: 食べる (ja) and "to eat" (en).
  final ja = File('test/fixtures/tts_ja.mp3').readAsBytesSync();
  final en = File('test/fixtures/tts_en.mp3').readAsBytesSync();

  test("Google's clips: MPEG-2 Layer III, 24 kHz mono, 192-byte frames of 24 ms", () {
    final f = firstFrame(ja)!;
    expect(f.sampleRate, 24000);
    expect(f.samples, 576);
    expect(f.ms, 24);
    expect(f.size, anyOf(192, 193));
    expect(f.sameFormat(firstFrame(en)!), isTrue, reason: 'Japanese and English can share one file');
  });

  test('every byte of a clip is whole frames, so its length is exact', () {
    expect(audioFrames(ja).length, ja.length);
    final ms = mp3DurationMs(ja);
    expect(ms, greaterThan(500));
    expect(ms % 24, 0, reason: 'a whole number of 24 ms frames');
  });

  test('an ID3v2 tag in front is stripped', () {
    final tag = Uint8List.fromList([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 5, 1, 2, 3, 4, 5]);
    final tagged = Uint8List.fromList([...tag, ...ja]);
    expect(audioFrames(tagged), ja);
  });

  test('trailing junk (an ID3v1 tag) is dropped', () {
    final withTag = Uint8List.fromList([...ja, ...('TAG'.codeUnits), ...List.filled(125, 0)]);
    expect(audioFrames(withTag), ja);
  });

  test('silence is valid frames in the same format, close to the asked length', () {
    final s = silence(firstFrame(ja)!, 1000);
    expect(mp3DurationMs(s), closeTo(1000, 24));
    expect(Mp3Frame.at(s, 0)!.sameFormat(firstFrame(ja)!), isTrue);
  });

  test('clips and silence join into one stream whose length adds up', () {
    final joined = Uint8List.fromList([...audioFrames(ja), ...silence(firstFrame(ja)!, 500), ...audioFrames(en)]);
    expect(mp3DurationMs(joined), closeTo(mp3DurationMs(ja) + 500 + mp3DurationMs(en), 24));
  });
}
