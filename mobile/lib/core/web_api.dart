import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'repository.dart';

final webApiProvider = Provider<WebApi>(
  (ref) => WebApi(ref.watch(supabaseProvider)),
);

/// Result of `/api/lookup`: the dictionary form Jisho resolves a conjugated
/// term to (担っています → 担う), its reading, and up to three senses.
class LookupResult {
  const LookupResult({required this.word, required this.reading, required this.meaning});
  final String word;
  final String reading;
  final String meaning;

  bool get isEmpty => word.isEmpty && reading.isEmpty && meaning.isEmpty;
}

class ExportedFile {
  const ExportedFile(this.filename, this.bytes);
  final String filename;
  final Uint8List bytes;
}

/// The Next.js routes Supabase alone can't serve. Lookup and translate are
/// unauthenticated; audio and export take the Supabase access token as a
/// Bearer header (web/src/lib/supabase/bearer.ts), so RLS still scopes them to
/// the caller — no service-role bypass anywhere.
///
/// Lookup and translate deliberately return empty results instead of throwing:
/// the web treats them as conveniences on top of manual entry, and so does
/// this. Audio and export do throw, because the caller has something to say.
class WebApi {
  WebApi(this._db, {http.Client? client}) : _http = client ?? http.Client();

  final SupabaseClient _db;
  final http.Client _http;

  bool get available => Config.hasWebApi;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${Config.webApiBase}$path').replace(queryParameters: query);

  Map<String, String> get _auth {
    final token = _db.auth.currentSession?.accessToken;
    if (token == null) throw StateError('not signed in');
    return {'Authorization': 'Bearer $token'};
  }

  Future<LookupResult> lookup(String term) async {
    final t = term.trim();
    if (!available || t.isEmpty) {
      return const LookupResult(word: '', reading: '', meaning: '');
    }
    try {
      final res = await _http
          .get(_uri('/api/lookup', {'term': t}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return const LookupResult(word: '', reading: '', meaning: '');
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return LookupResult(
        word: j['word'] as String? ?? '',
        reading: j['reading'] as String? ?? '',
        meaning: j['meaning'] as String? ?? '',
      );
    } catch (_) {
      return const LookupResult(word: '', reading: '', meaning: '');
    }
  }

  /// English (or anything) → Mongolian. Empty string on any failure.
  Future<String> translate(String text) async {
    final t = text.trim();
    if (!available || t.isEmpty) return '';
    try {
      final res = await _http
          .get(_uri('/api/translate', {'text': t}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return '';
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return j['mongolian'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Generates the word's pronunciation server-side (same TTS as the web) and
  /// returns its `word-audio` storage path. The route also writes
  /// `words.audio_path`, so every client sees the clip afterwards.
  Future<String> generateWordAudio(String wordId) async {
    if (!available) throw StateError('WEB_API_BASE is not configured');
    final res = await _http
        .post(_uri('/api/words/$wordId/audio'), headers: _auth)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('audio ${res.statusCode}: ${res.body}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['audio_path'] as String;
  }

  /// [format] is `txt` or `apkg`.
  Future<ExportedFile> exportDeck(String deckId, String format) async {
    if (!available) throw StateError('WEB_API_BASE is not configured');
    final res = await _http
        .post(_uri('/api/decks/$deckId/$format'), headers: _auth)
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) {
      throw Exception('export ${res.statusCode}: ${res.body}');
    }
    final disposition = res.headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
    return ExportedFile(match?.group(1) ?? 'deck.$format', res.bodyBytes);
  }
}
