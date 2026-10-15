import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'tts_clips.dart' show fnv1a64;

/// One instance for the add and edit forms, so their lookups share the
/// on-disk cache with the audio decks'.
final exampleSentencesProvider = Provider<ExampleSentences>((ref) => ExampleSentences());

/// An example sentence for a word, with its English translation.
class Example {
  const Example(this.ja, this.en);
  final String ja;
  final String en;

  Map<String, dynamic> toJson() => {'ja': ja, 'en': en};

  static Example? fromJson(Map<String, dynamic> j) {
    final ja = j['ja'], en = j['en'];
    return ja is String && en is String && ja.isNotEmpty && en.isNotEmpty
        ? Example(ja, en)
        : null;
  }
}

/// Example sentences for audio decks, from Tatoeba — a free, keyless corpus
/// of Japanese sentences with human English translations (CC BY 2.0 FR).
/// Fetched from the phone directly, like the speech, and cached on disk by
/// word, so a rebuilt deck doesn't ask again.
///
/// Fetched at build time rather than stored on the word: nothing else uses
/// them yet, and it needs no migration. A word Tatoeba has nothing good for
/// is simply spoken without a sentence.
class ExampleSentences {
  ExampleSentences({http.Client? client, Future<Directory> Function()? dir})
    : _http = client ?? http.Client(),
      _dir = dir ?? getApplicationSupportDirectory;

  final http.Client _http;
  final Future<Directory> Function() _dir;

  /// "Tatoeba has nothing for this word" is cached too, but retried after
  /// this long — the corpus grows.
  static const retryNoneAfter = Duration(days: 30);

  /// The sentence for [term], or null when there's no good one or the
  /// request failed. A failed request isn't cached, so the next build retries.
  Future<Example?> find(String term) async {
    final t = term.trim();
    if (t.isEmpty) return null;
    final file = File('${(await _dir()).path}/examples/${fnv1a64(t)}.json');
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final hit = Example.fromJson(j);
        final at = DateTime.tryParse(j['at'] as String? ?? '');
        if (hit != null ||
            (at != null && DateTime.now().difference(at) < retryNoneAfter)) {
          return hit;
        }
      }
    } catch (_) {}

    final Example? picked;
    try {
      final res = await _http
          .get(
            Uri.https('api.tatoeba.org', '/unstable/sentences', {
              'lang': 'jpn',
              'q': t,
              'sort': 'relevance',
              'trans:lang': 'eng',
              'showtrans': 'matching',
              'limit': '50',
            }),
            headers: const {
              'User-Agent': 'Mozilla/5.0 (compatible; Hanko/1.0)',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      picked = pickExample(t, body is Map ? body['data'] : null);
    } catch (_) {
      return null;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({...?picked?.toJson(), 'at': DateTime.now().toIso8601String()}),
      );
    } catch (_) {}
    return picked;
  }
}

/// Japanese sentences longer than this are hard to follow by ear.
const maxSentenceChars = 32;

/// Spoken translations longer than this drag.
const maxTranslationChars = 140;

final _kanji = RegExp(r'[㐀-䶿一-鿿々]');
final _hiragana = RegExp(r'^[ぁ-ゟ]$');

bool _isKanji(String ch) => ch.isNotEmpty && _kanji.hasMatch(ch);

/// The part of [term] that stays put when it's conjugated: 食べる → 食べ
/// (食べた, 食べます), 担う → 担 (担った), 勉強する → 勉強. A term with no
/// kanji or no trailing kana is its own stem.
String wordStem(String term) {
  if (term.length > 2 && term.endsWith('する')) {
    return term.substring(0, term.length - 2);
  }
  if (term.length >= 2 &&
      _kanji.hasMatch(term) &&
      _hiragana.hasMatch(term[term.length - 1])) {
    return term.substring(0, term.length - 1);
  }
  return term;
}

/// Whether [sentence] uses [s] as a word rather than as part of a longer
/// kanji compound: a kanji edge of [s] must not touch another kanji, so 群 is
/// found in 羊の群を見た but not in 抜群, and 担 (担う) not in 担当.
bool usesAsWord(String sentence, String s) {
  if (s.isEmpty) return false;
  for (var i = sentence.indexOf(s); i >= 0; i = sentence.indexOf(s, i + 1)) {
    final before = i > 0 ? sentence[i - 1] : '';
    final end = i + s.length;
    final after = end < sentence.length ? sentence[end] : '';
    if (_isKanji(s[0]) && _isKanji(before)) continue;
    if (_isKanji(s[s.length - 1]) && _isKanji(after)) continue;
    return true;
  }
  return false;
}

/// The best sentence for [term] out of Tatoeba's results (most relevant
/// first): approved, with an English translation, short enough to follow by
/// ear, and using the word itself — the exact form preferred over a
/// conjugated one, a mid-length sentence over a bare one-word "食べる。".
Example? pickExample(String term, Object? data) {
  if (data is! List) return null;
  final stem = wordStem(term);
  Example? best;
  var bestScore = 1 << 30;
  for (final s in data) {
    if (s is! Map || s['is_unapproved'] == true) continue;
    final ja = (s['text'] as String? ?? '').trim();
    if (ja.isEmpty || ja.length > maxSentenceChars) continue;
    final exact = usesAsWord(ja, term);
    if (!exact && (stem == term || !usesAsWord(ja, stem))) continue;

    final en = _translation(s['translations']);
    if (en == null) continue;

    final len = ja.length;
    final shape = len < 8 ? 8 - len : (len > 24 ? len - 24 : 0);
    final score = (exact ? 0 : 10) + shape;
    if (score < bestScore) {
      best = Example(ja, en);
      bestScore = score;
    }
  }
  return best;
}

/// The first usable English translation, a direct one if there is one.
String? _translation(Object? list) {
  if (list is! List) return null;
  String? indirect;
  for (final t in list) {
    if (t is! Map || t['lang'] != 'eng' || t['is_unapproved'] == true) continue;
    final text = (t['text'] as String? ?? '').trim();
    if (text.isEmpty || text.length > maxTranslationChars) continue;
    if (t['is_direct'] != false) return text;
    indirect ??= text;
  }
  return indirect;
}
