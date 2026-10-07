import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Speech clips for audio decks, from the same keyless Google Translate voice
/// the web's `tts.ts` uses — fetched from the phone directly (no server of
/// ours), cached on disk by language and text so a deck regenerates fast and
/// a word shared by two decks is fetched once.
///
/// Japanese and English only: the endpoint has no Mongolian voice (it answers
/// 400), and no phone engine ships one either. Mongolian meanings are shown in
/// the player as text instead.
class TtsClips {
  TtsClips({http.Client? client, Future<Directory> Function()? dir})
    : _http = client ?? http.Client(),
      _dir = dir ?? getApplicationSupportDirectory;

  final http.Client _http;
  final Future<Directory> Function() _dir;

  /// The endpoint rejects long text; a meaning is cut at a natural break
  /// before this.
  static const maxChars = 180;

  /// A spoken word or meaning is a few KB; anything far bigger isn't a clip.
  static const maxBytes = 512 * 1024;

  /// The clip for [text] in [lang] ('ja' or 'en'), or null if it can't be had
  /// (offline and not cached, or the endpoint refused).
  Future<Uint8List?> clip(String text, String lang) async {
    final t = speakable(text);
    if (t.isEmpty) return null;
    final file = File('${(await _dir()).path}/tts/${lang}_${fnv1a64(t)}.mp3');
    try {
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    try {
      final res = await _http
          .get(
            Uri.https('translate.google.com', '/translate_tts', {
              'ie': 'UTF-8',
              'client': 'tw-ob',
              'tl': lang,
              'q': t,
            }),
            headers: const {
              'User-Agent': 'Mozilla/5.0 (compatible; Hanko/1.0)',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 ||
          !(res.headers['content-type'] ?? '').contains('audio') ||
          res.bodyBytes.length > maxBytes) {
        return null;
      }
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(res.bodyBytes);
      } catch (_) {}
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}

/// Text as it should be spoken: whitespace collapsed, and long text cut at the
/// last sense or comma break that fits ("to eat; to live on (e.g. a salary)"
/// becomes "to eat" only if the whole is too long).
String speakable(String text) {
  var t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= TtsClips.maxChars) return t;
  for (final sep in ['; ', ', ']) {
    final cut = t.lastIndexOf(sep, TtsClips.maxChars);
    if (cut > 0) return t.substring(0, cut);
  }
  return t.substring(0, TtsClips.maxChars);
}

/// A stable 64-bit FNV-1a hash as hex — a cache file name that doesn't change
/// between app versions (Dart's String.hashCode isn't guaranteed to).
String fnv1a64(String s) {
  var h = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final b in utf8.encode(s)) {
    h = ((h ^ BigInt.from(b)) * prime) & mask;
  }
  return h.toRadixString(16).padLeft(16, '0');
}
