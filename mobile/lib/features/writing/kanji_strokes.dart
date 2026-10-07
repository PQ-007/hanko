import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'stroke_grader.dart';
import 'svg_path.dart';

/// One kanji's strokes in writing order, from KanjiVG
/// (https://kanjivg.tagaini.net, © Ulrich Apel, CC BY-SA 3.0). Coordinates
/// are in KanjiVG's 109×109 box.
class KanjiStrokes {
  KanjiStrokes(this.char, this.data)
    : paths = [for (final d in data) parseSvgPath(d)],
      starts = [for (final d in data) svgPathStart(d) ?? Offset.zero];

  static const box = 109.0;

  final String char;

  /// Raw path data per stroke, in order.
  final List<String> data;
  final List<Path> paths;
  final List<Offset> starts;

  int get count => data.length;

  /// Each stroke as a polyline, for grading handwriting against.
  late final List<List<Offset>> polylines = [
    for (final p in paths) pathPoints(p),
  ];
}

/// Stroke paths from a KanjiVG SVG, in stroke order. Only the stroke paths
/// (ids ending -s1, -s2, …) are taken; KanjiVG's grouping elements and the
/// stroke-number layer are ignored.
List<String> parseKanjiVg(String svg) {
  final strokes = <(int, String)>[];
  for (final m in RegExp(r'<path\b[^>]*>').allMatches(svg)) {
    final tag = m.group(0)!;
    final id = RegExp(r'id="[^"]*-s(\d+)"').firstMatch(tag);
    final d = RegExp(r'\sd="([^"]+)"').firstMatch(tag);
    if (id != null && d != null) {
      strokes.add((int.parse(id.group(1)!), d.group(1)!));
    }
  }
  strokes.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final s in strokes) s.$2];
}

/// KanjiVG names files by the code point, five hex digits: 食 → 098df.svg.
String kanjiVgFile(String char) =>
    '${char.runes.first.toRadixString(16).padLeft(5, '0')}.svg';

final kanjiStrokesProvider = Provider<KanjiStrokeStore>(
  (ref) => KanjiStrokeStore(),
);

/// Fetches stroke data per kanji on first use and keeps it on the phone, so a
/// lesson needs a connection only the first time a kanji appears. Bundling
/// all of KanjiVG (~6,700 kanji) would add tens of MB for characters most
/// learners never meet.
class KanjiStrokeStore {
  KanjiStrokeStore({http.Client? client, Future<Directory> Function()? dir})
    : _http = client ?? http.Client(),
      _dir = dir ?? getApplicationSupportDirectory;

  final http.Client _http;
  final Future<Directory> Function() _dir;
  final _memory = <String, KanjiStrokes?>{};

  static const _sources = [
    'https://raw.githubusercontent.com/KanjiVG/kanjivg/master/kanji/',
    'https://cdn.jsdelivr.net/gh/KanjiVG/kanjivg@master/kanji/',
  ];

  /// The strokes for [char], or null when there's no data and no connection
  /// to get it — the lesson then falls back to writing without a guide.
  Future<KanjiStrokes?> load(String char) async {
    if (_memory.containsKey(char)) return _memory[char];
    final file = File('${(await _dir()).path}/kanjivg/${kanjiVgFile(char)}');
    String? svg;
    try {
      if (await file.exists()) svg = await file.readAsString();
    } catch (_) {}
    if (svg == null) {
      for (final base in _sources) {
        try {
          final res = await _http
              .get(Uri.parse('$base${kanjiVgFile(char)}'))
              .timeout(const Duration(seconds: 10));
          // A KanjiVG file is a few KB; refuse anything that isn't one.
          if (res.statusCode == 200 && res.bodyBytes.length < 256 * 1024) {
            // KanjiVG is UTF-8 (stroke types like ㇒ are in the markup);
            // decode explicitly rather than trust each CDN's content type.
            svg = utf8.decode(res.bodyBytes);
            try {
              await file.parent.create(recursive: true);
              await file.writeAsString(svg);
            } catch (_) {}
            break;
          }
        } catch (_) {}
      }
    }
    final data = svg == null ? const <String>[] : parseKanjiVg(svg);
    final strokes = data.isEmpty ? null : KanjiStrokes(char, data);
    // A miss is only remembered for this session: the next one may be online.
    _memory[char] = strokes;
    return strokes;
  }

  /// Loads everything a lesson needs up front, so it runs without a
  /// connection once started.
  Future<void> prefetch(Iterable<String> chars) async {
    // A few at a time: a hunt's whole queue can be a hundred kanji, and a
    // hundred parallel requests would compete with the fight for the network.
    final pending = chars.toSet().toList();
    Future<void> worker() async {
      while (pending.isNotEmpty) {
        await load(pending.removeLast());
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  }
}
