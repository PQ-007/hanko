import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/library.dart';
import 'mp3.dart';
import 'tts_clips.dart';

/// How a deck is turned into audio.
class AudioOptions {
  const AudioOptions({
    this.english = true,
    this.repeat = 1,
    this.pauseMs = 1500,
    this.shuffle = false,
  });

  /// Speak the English meaning after the Japanese.
  final bool english;

  /// Times each word is spoken (with its meaning) before the next.
  final int repeat;

  /// Silence after each spoken part — time to repeat it aloud.
  final int pauseMs;

  /// Random order instead of the deck's.
  final bool shuffle;

  Map<String, dynamic> toJson() => {
    'english': english,
    'repeat': repeat,
    'pauseMs': pauseMs,
    'shuffle': shuffle,
  };

  factory AudioOptions.fromJson(Map<String, dynamic> j) => AudioOptions(
    english: j['english'] as bool? ?? true,
    repeat: (j['repeat'] as num?)?.toInt() ?? 1,
    pauseMs: (j['pauseMs'] as num?)?.toInt() ?? 1500,
    shuffle: j['shuffle'] as bool? ?? false,
  );
}

/// Where a word starts in the file, and what to show while it plays.
class AudioCue {
  const AudioCue({
    required this.startMs,
    required this.term,
    this.reading,
    this.meaningMn,
    this.meaning,
  });
  final int startMs;
  final String term;
  final String? reading;
  final String? meaningMn;
  final String? meaning;

  Map<String, dynamic> toJson() => {
    'startMs': startMs,
    'term': term,
    'reading': ?reading,
    'meaningMn': ?meaningMn,
    'meaning': ?meaning,
  };

  factory AudioCue.fromJson(Map<String, dynamic> j) => AudioCue(
    startMs: (j['startMs'] as num).toInt(),
    term: j['term'] as String,
    reading: j['reading'] as String?,
    meaningMn: j['meaningMn'] as String?,
    meaning: j['meaning'] as String?,
  );
}

/// A generated audio deck: the MP3 and what's in it.
class AudioDeck {
  const AudioDeck({
    required this.deckId,
    required this.deckName,
    required this.path,
    required this.durationMs,
    required this.createdAt,
    required this.options,
    required this.cues,
    this.skipped = 0,
  });

  final String deckId;
  final String deckName;
  final String path;
  final int durationMs;
  final DateTime createdAt;
  final AudioOptions options;
  final List<AudioCue> cues;

  /// Words left out because their speech couldn't be fetched.
  final int skipped;

  /// The word playing at [ms].
  int cueAt(int ms) {
    var i = 0;
    while (i + 1 < cues.length && cues[i + 1].startMs <= ms) {
      i++;
    }
    return i;
  }

  Map<String, dynamic> toJson() => {
    'deckId': deckId,
    'deckName': deckName,
    'path': path,
    'durationMs': durationMs,
    'createdAt': createdAt.toIso8601String(),
    'options': options.toJson(),
    'cues': [for (final c in cues) c.toJson()],
    'skipped': skipped,
  };

  factory AudioDeck.fromJson(Map<String, dynamic> j) => AudioDeck(
    deckId: j['deckId'] as String,
    deckName: j['deckName'] as String? ?? '',
    path: j['path'] as String,
    durationMs: (j['durationMs'] as num).toInt(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    options: AudioOptions.fromJson(
      Map<String, dynamic>.from(j['options'] as Map),
    ),
    cues: [
      for (final c in j['cues'] as List)
        AudioCue.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    skipped: (j['skipped'] as num?)?.toInt() ?? 0,
  );
}

/// One spoken part of the deck, before fetching.
class SpokenPart {
  const SpokenPart(this.wordIndex, this.text, this.lang);
  final int wordIndex;
  final String text;
  final String lang;
}

/// What gets spoken, in order: for each word, its Japanese (the reading when
/// there is one — kana says how it's pronounced, where kanji can be misread by
/// the voice), then its English meaning, repeated [AudioOptions.repeat] times.
List<SpokenPart> planParts(List<Word> words, AudioOptions o) => [
  for (var w = 0; w < words.length; w++)
    for (var r = 0; r < o.repeat; r++) ...[
      SpokenPart(
        w,
        (words[w].reading?.isNotEmpty ?? false)
            ? words[w].reading!
            : words[w].term,
        'ja',
      ),
      if (o.english && (words[w].meaning?.isNotEmpty ?? false))
        SpokenPart(w, words[w].meaning!, 'en'),
    ],
];

/// Joins fetched clips into one MP3 with [AudioOptions.pauseMs] of silence
/// after each, and records where each word starts. A word whose Japanese
/// clip is missing is left out whole (its meaning alone would be confusing);
/// a missing English clip just drops the meaning.
({Uint8List mp3, List<int> starts, List<int> kept}) assemble(
  List<Word> words,
  List<SpokenPart> parts,
  List<Uint8List?> clips,
  AudioOptions o,
) {
  final format = clips
      .whereType<Uint8List>()
      .map(firstFrame)
      .whereType<Mp3Frame>()
      .firstOrNull;
  final out = BytesBuilder(copy: false);
  final starts = <int>[];
  final kept = <int>[];
  if (format == null) return (mp3: Uint8List(0), starts: starts, kept: kept);
  final gap = silence(format, o.pauseMs.toDouble());
  final missingJa = {
    for (var i = 0; i < parts.length; i++)
      if (parts[i].lang == 'ja' && clips[i] == null) parts[i].wordIndex,
  };
  var ms = 0.0;
  var lastWord = -1;
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    final clip = clips[i];
    if (missingJa.contains(p.wordIndex) || clip == null) continue;
    final frames = audioFrames(clip);
    final f = firstFrame(clip);
    if (frames.isEmpty || f == null || !f.sameFormat(format)) continue;
    if (p.wordIndex != lastWord) {
      lastWord = p.wordIndex;
      starts.add(ms.round());
      kept.add(p.wordIndex);
    }
    out
      ..add(frames)
      ..add(gap);
    ms += mp3DurationMs(frames) + mp3DurationMs(gap);
  }
  return (mp3: out.takeBytes(), starts: starts, kept: kept);
}

/// [assemble] on another isolate. A function of its own so the closure
/// sent there captures only these arguments — a closure made inside `build`
/// would drag along that scope's pending downloads, which can't be sent.
Future<({Uint8List mp3, List<int> starts, List<int> kept, double ms})>
_assembleOffThread(
  List<Word> words,
  List<SpokenPart> parts,
  List<Uint8List?> clips,
  AudioOptions options,
) => Isolate.run(() {
  final r = assemble(words, parts, clips, options);
  return (mp3: r.mp3, starts: r.starts, kept: r.kept, ms: mp3DurationMs(r.mp3));
});

final audioDeckStoreProvider = Provider<AudioDeckStore>(
  (ref) => AudioDeckStore(TtsClips()),
);

/// Builds, lists and deletes audio decks: `audio_decks/<deckId>.mp3` plus a
/// `.json` beside it with the options, length and word cues. Files, not a
/// table — nothing queries them, and the MP3 has to be a file to be shared.
class AudioDeckStore {
  AudioDeckStore(this._clips, {Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationDocumentsDirectory;

  final TtsClips _clips;
  final Future<Directory> Function() _dir;

  /// At most this many clip requests at once: a deck of a hundred words is
  /// a few hundred requests to a free endpoint.
  static const _concurrency = 3;

  Future<Directory> _folder() async {
    final d = Directory('${(await _dir()).path}/audio_decks');
    await d.create(recursive: true);
    return d;
  }

  Future<List<AudioDeck>> list() async {
    final out = <AudioDeck>[];
    try {
      await for (final f in (await _folder()).list()) {
        if (f is File && f.path.endsWith('.json')) {
          try {
            final deck = AudioDeck.fromJson(
              jsonDecode(await f.readAsString()) as Map<String, dynamic>,
            );
            if (await File(deck.path).exists()) out.add(deck);
          } catch (_) {}
        }
      }
    } catch (_) {}
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// A deck id as a file name: ids are server UUIDs, but nothing outside
  /// letters, digits and dashes is let near a path.
  static String fileStem(String deckId) =>
      deckId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');

  Future<void> delete(String deckId) async {
    final d = await _folder();
    for (final ext in ['mp3', 'json']) {
      final f = File('${d.path}/${fileStem(deckId)}.$ext');
      if (await f.exists()) await f.delete();
    }
  }

  /// Builds the deck's audio, reporting `(done, total)` clips as it goes.
  /// Returns null when nothing could be fetched at all (offline with an empty
  /// cache).
  Future<AudioDeck?> build({
    required String deckId,
    required String deckName,
    required List<Word> words,
    required AudioOptions options,
    void Function(int done, int total)? onProgress,
  }) async {
    final ordered = options.shuffle ? ([...words]..shuffle(Random())) : words;
    final parts = planParts(ordered, options);
    final clips = List<Uint8List?>.filled(parts.length, null);
    // The same text (a repeat, a shared meaning) is fetched once.
    final unique = <String, Future<Uint8List?>>{};
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < parts.length) {
        final i = next++;
        final p = parts[i];
        clips[i] = await (unique['${p.lang}|${p.text}'] ??= _clips.clip(
          p.text,
          p.lang,
        ));
        onProgress?.call(++done, parts.length);
      }
    }

    await Future.wait([for (var w = 0; w < _concurrency; w++) worker()]);
    // Joining a big deck walks megabytes of frames. Dart shares Android's
    // main thread (Flutter 3.29+), so doing it here would freeze the app —
    // long enough on a large deck for an ANR. It runs on its own isolate.
    final result = await _assembleOffThread(ordered, parts, clips, options);
    if (result.mp3.isEmpty) return null;

    final dir = await _folder();
    final mp3 = File('${dir.path}/${fileStem(deckId)}.mp3');
    await mp3.writeAsBytes(result.mp3, flush: true);
    final deck = AudioDeck(
      deckId: deckId,
      deckName: deckName,
      path: mp3.path,
      durationMs: result.ms.round(),
      createdAt: DateTime.now(),
      options: options,
      cues: [
        for (var k = 0; k < result.kept.length; k++)
          AudioCue(
            startMs: result.starts[k],
            term: ordered[result.kept[k]].term,
            reading: ordered[result.kept[k]].reading,
            meaningMn: ordered[result.kept[k]].meaningMn,
            meaning: ordered[result.kept[k]].meaning,
          ),
      ],
      skipped: ordered.length - result.kept.length,
    );
    await File(
      '${dir.path}/${fileStem(deckId)}.json',
    ).writeAsString(jsonEncode(deck.toJson()));
    return deck;
  }
}
