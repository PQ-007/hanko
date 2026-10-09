import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final dictionaryProvider = Provider<Dictionary>((ref) => Dictionary());

/// Result of a Jisho lookup: the dictionary form Jisho resolves a conjugated
/// term to (担っています → 担う), its reading, and up to three senses.
class LookupResult {
  const LookupResult({required this.word, required this.reading, required this.meaning});
  final String word;
  final String reading;
  final String meaning;

  static const empty = LookupResult(word: '', reading: '', meaning: '');
  bool get isEmpty => word.isEmpty && reading.isEmpty && meaning.isEmpty;
}

/// Dictionary lookup and EN→MN translation, called straight from the phone —
/// no backend of our own in between, so the app stands alone.
///
/// Ports of the web's web/src/lib/jisho.ts and translate.ts, against the same
/// two public endpoints with the same parsing, so both clients fill a word in
/// identically. Both are conveniences on top of manual entry: any failure
/// (offline, endpoint down, odd response) returns an empty result rather than
/// throwing.
class Dictionary {
  Dictionary({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _translations = <String, String>{};

  /// Jisho blocks bare default client user-agents (it 403s Node's "node"), so
  /// identify the app explicitly rather than rely on Dart's default.
  static const _headers = {'User-Agent': 'Hanko/1.0 (mobile; +vocab app)'};

  Future<LookupResult> lookup(String term) async {
    final t = term.trim();
    if (t.isEmpty) return LookupResult.empty;
    try {
      final res = await _http
          .get(
            Uri.https('jisho.org', '/api/v1/search/words', {'keyword': t}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return LookupResult.empty;
      return parseJisho(jsonDecode(utf8.decode(res.bodyBytes)), term: t);
    } catch (_) {
      return LookupResult.empty;
    }
  }

  /// Anything (usually English) → Mongolian. Empty string on any failure.
  Future<String> translate(String text) async {
    final t = text.trim();
    if (t.isEmpty) return '';
    final cached = _translations[t];
    if (cached != null) return cached;
    try {
      final res = await _http
          .get(
            Uri.https('translate.googleapis.com', '/translate_a/single', {
              'client': 'gtx',
              'sl': 'auto',
              'tl': 'mn',
              'dt': 't',
              'q': stripNotes(t).isEmpty ? t : stripNotes(t),
            }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return '';
      final result = parseTranslation(jsonDecode(utf8.decode(res.bodyBytes)), source: t);
      if (result.isNotEmpty) _translations[t] = result;
      return result;
    } catch (_) {
      return '';
    }
  }
}

/// Jisho's results → dictionary form, reading, and the first three senses
/// compacted by [compactGloss] (jisho.ts `parseJisho`, same rules).
///
/// The entry and writing are chosen to keep [term] as typed when Jisho knows
/// it: Jisho lists an entry under its most common spelling, so the first
/// entry's first writing would swap a rarer kanji the user deliberately
/// entered (籠る, 附属) for the common one (篭る, 付属). Only when no entry has
/// [term] as a writing — a conjugated form like 食べました — is the first
/// entry's main writing used, which is what turns it into 食べる.
LookupResult parseJisho(Object? data, {String term = ''}) {
  if (data is! Map) return LookupResult.empty;
  final entries = data['data'];
  if (entries is! List || entries.isEmpty || entries.first is! Map) return LookupResult.empty;

  List<Map> writingsOf(Object? entry) {
    final japanese = entry is Map ? entry['japanese'] : null;
    return japanese is List ? japanese.whereType<Map>().toList() : const [];
  }

  var entry = entries.first as Map;
  Map jp = writingsOf(entry).firstOrNull ?? const {};
  if (term.isNotEmpty) {
    for (final e in entries.whereType<Map>()) {
      final exact = writingsOf(e).where((w) => w['word'] == term).firstOrNull;
      if (exact != null) {
        entry = e;
        jp = exact;
        break;
      }
    }
  }
  final reading = jp['reading'] as String? ?? '';
  // Dictionary form: the kanji writing, or the slug, or the reading (kana words).
  final word = jp['word'] as String? ?? entry['slug'] as String? ?? reading;

  final senses = entry['senses'];
  final meaning = senses is List
      ? compactGloss(senses
          .take(3)
          .map((s) => s is Map && s['english_definitions'] is List
              ? (s['english_definitions'] as List).join(', ')
              : '')
          .join('; '))
      : '';

  return LookupResult(word: word, reading: reading, meaning: meaning);
}

/// Google's `[[["translated","source",...], ...], ...]` → joined text, then
/// [compactGloss] (translate.ts `translateToMongolian`).
String parseTranslation(Object? data, {required String source}) {
  if (data is! List || data.isEmpty || data.first is! List) return '';
  final result = (data.first as List)
      .map((seg) => seg is List && seg.isNotEmpty && seg.first is String ? seg.first as String : '')
      .where((s) => s.isNotEmpty)
      .join()
      .trim();
  return compactGloss(result);
}

/// Most items a gloss keeps, and the length past which no further item is
/// added (the first is always kept). Same as gloss.ts.
const maxGlossItems = 3;
const maxGlossChars = 40;

/// Drops bracketed notes: Jisho's "(e.g. a salary)", "(a task)" and the like.
String stripNotes(String text) => text
    .replaceAll(RegExp(r'\([^()]*\)|（[^（）]*）|\[[^\]]*\]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Dictionary meanings are synonym lists split by "," and ";", and Google maps
/// many of them to the same Mongolian word ("болгоомжтой, болгоомжтой;
/// болгоомжтой"). Keep each item once, notes stripped, at most
/// [maxGlossItems] and about [maxGlossChars] long — meaning_mn is
/// shown on cards and fed to audio/video reviews. Used for both the English
/// meaning ([parseJisho]) and its translation (gloss.ts, same rules).
String compactGloss(String text) {
  final seen = <String>{};
  final items = <String>[];
  var length = 0;
  for (final raw in text.split(RegExp(r'[,;、，；\n]'))) {
    final item = stripNotes(raw).replaceAll(RegExp(r'^[\s.:-]+|[\s.:-]+$'), '');
    if (item.isEmpty || !seen.add(item.toLowerCase())) continue;
    if (items.isNotEmpty && length + 2 + item.length > maxGlossChars) break;
    items.add(item);
    length += (items.length > 1 ? 2 : 0) + item.length;
    if (items.length == maxGlossItems) break;
  }
  return items.join(', ');
}
