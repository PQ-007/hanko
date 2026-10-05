import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/audio/audio_deck.dart';
import 'package:mobile/features/audio/mp3.dart';
import 'package:mobile/features/audio/tts_clips.dart';
import 'package:mobile/models/library.dart';

Word word(String id, String term, {String? reading, String? meaning, String? mn}) => Word(
      id: id,
      deckId: 'd',
      term: term,
      reading: reading,
      meaning: meaning,
      meaningMn: mn,
      dateAdded: DateTime(2026),
    );

void main() {
  final ja = File('test/fixtures/tts_ja.mp3').readAsBytesSync();
  final en = File('test/fixtures/tts_en.mp3').readAsBytesSync();
  final words = [
    word('1', '食べる', reading: 'たべる', meaning: 'to eat', mn: 'идэх'),
    word('2', 'ありがとう', meaning: 'thank you'),
  ];

  test('each word: its reading (else the term), then English, repeated', () {
    final parts = planParts(words, const AudioOptions(repeat: 2));
    expect(parts.map((p) => '${p.wordIndex}:${p.lang}:${p.text}'), [
      '0:ja:たべる', '0:en:to eat', '0:ja:たべる', '0:en:to eat',
      '1:ja:ありがとう', '1:en:thank you', '1:ja:ありがとう', '1:en:thank you',
    ]);
    expect(planParts(words, const AudioOptions(english: false)).map((p) => p.lang), ['ja', 'ja']);
  });

  test('assembled: clips with pauses, each word cued where it starts', () {
    const o = AudioOptions(pauseMs: 1000);
    final parts = planParts(words, o);
    final clips = [for (final p in parts) p.lang == 'ja' ? ja : en];
    final r = assemble(words, parts, clips, o);
    final perWord = mp3DurationMs(ja) + mp3DurationMs(en) + 2 * 1000;
    expect(r.kept, [0, 1]);
    expect(r.starts.first, 0);
    expect(r.starts[1], closeTo(perWord, 50));
    expect(mp3DurationMs(r.mp3), closeTo(2 * perWord, 100));
  });

  test("a word whose Japanese couldn't be fetched is left out whole", () {
    const o = AudioOptions();
    final parts = planParts(words, o);
    final clips = <Uint8List?>[null, en, ja, en];
    final r = assemble(words, parts, clips, o);
    expect(r.kept, [1], reason: 'no meaning without its word');
    expect(r.starts, [0]);
  });

  test('a missing English clip only drops the meaning', () {
    const o = AudioOptions();
    final parts = planParts(words, o);
    final r = assemble(words, parts, <Uint8List?>[ja, null, ja, en], o);
    expect(r.kept, [0, 1]);
  });

  test('the cue playing at a moment', () {
    final deck = AudioDeck(
      deckId: 'd', deckName: 'n', path: 'p', durationMs: 9000, createdAt: DateTime(2026),
      options: const AudioOptions(),
      cues: const [AudioCue(startMs: 0, term: 'a'), AudioCue(startMs: 3000, term: 'b'), AudioCue(startMs: 6000, term: 'c')],
    );
    expect(deck.cueAt(0), 0);
    expect(deck.cueAt(2999), 0);
    expect(deck.cueAt(3000), 1);
    expect(deck.cueAt(8000), 2);
    expect(AudioDeck.fromJson(deck.toJson()).cues.last.term, 'c', reason: 'survives its JSON sidecar');
  });

  test('build: fetches each text once, writes the MP3 and its sidecar, lists it', () async {
    final tmp = Directory.systemTemp.createTempSync();
    var requests = 0;
    final clips = TtsClips(
      client: MockClient((req) async {
        requests++;
        final isJa = req.url.queryParameters['tl'] == 'ja';
        return http.Response.bytes(isJa ? ja : en, 200, headers: {'content-type': 'audio/mpeg'});
      }),
      dir: () async => tmp,
    );
    final store = AudioDeckStore(clips, dir: () async => tmp);
    final deck = await store.build(deckId: 'd1', deckName: 'N1', words: words, options: const AudioOptions(repeat: 3));
    expect(requests, 4, reason: '2 words x (ja + en), repeats reuse the clip');
    expect(deck!.cues.map((c) => c.term), ['食べる', 'ありがとう']);
    expect(File(deck.path).existsSync(), isTrue);
    expect((await store.list()).single.deckId, 'd1');

    // Rebuilding hits the disk cache, not the network.
    await store.build(deckId: 'd1', deckName: 'N1', words: words, options: const AudioOptions());
    expect(requests, 4);

    await store.delete('d1');
    expect(await store.list(), isEmpty);
  });

  test('long meanings are cut at a sense break, not mid-word', () {
    final long = List.filled(30, 'to eat; to live on').join('; ');
    final s = speakable(long);
    expect(s.length, lessThanOrEqualTo(TtsClips.maxChars));
    expect(s.endsWith('on') || s.endsWith('eat'), isTrue);
    expect(fnv1a64('食べる'), fnv1a64('食べる'));
    expect(fnv1a64('a'), isNot(fnv1a64('b')));
  });
}
