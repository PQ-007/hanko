import 'dart:ui';

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../../core/strings.dart';
import 'kanji_strokes.dart';
import 'stroke_grader.dart';
import 'writing_rules.dart';

/// ML Kit's Japanese handwriting model: downloaded once, then on-device.
const handwritingModel = 'ja';

/// Whether the handwriting model is on the phone. With [download], fetches it
/// if not (any connection, not just Wi-Fi) and reports whether that worked.
Future<bool> handwritingReady({bool download = false}) async {
  try {
    final manager = mlkit.DigitalInkRecognizerModelManager();
    if (await manager.isModelDownloaded(handwritingModel)) return true;
    if (!download) return false;
    return await manager.downloadModel(handwritingModel, isWifiRequired: false);
  } catch (_) {
    return false;
  }
}

/// One checked kanji.
class KanjiCheck {
  const KanjiCheck({required this.ok, required this.guesses, this.grade});
  final bool ok;

  /// What the recogniser read, best first.
  final List<String> guesses;

  /// The stroke-by-stroke verdict, when there's stroke data for the kanji.
  final StrokeGrade? grade;
}

/// Checks one handwritten kanji — shared by the writing lessons and Monster
/// Hunt's writing questions, so both judge handwriting identically.
///
/// Both checks have to agree: the strokes (count, order, direction,
/// placement — what a recogniser can't see) and the recogniser (the overall
/// shape, which the per-stroke tolerances are too loose to pin down alone).
/// Without stroke data for the kanji, the recogniser decides alone.
class KanjiChecker {
  final _recognizer = mlkit.DigitalInkRecognizer(languageCode: handwritingModel);

  Future<KanjiCheck> check({
    required String target,
    required List<List<mlkit.StrokePoint>> ink,
    required Size area,
    KanjiStrokes? strokes,
    String preContext = '',
  }) async {
    List<String> guesses;
    try {
      final drawing = mlkit.Ink()..strokes = [for (final s in ink) mlkit.Stroke()..points = s];
      final result = await _recognizer.recognize(
        drawing,
        context: mlkit.DigitalInkRecognitionContext(
          preContext: preContext,
          writingArea: mlkit.WritingArea(width: area.width, height: area.height),
        ),
      );
      guesses = [for (final c in result) c.text];
    } catch (_) {
      guesses = const [];
    }
    final grade = strokes == null
        ? null
        : gradeStrokes([for (final s in ink) [for (final p in s) Offset(p.x, p.y)]], strokes.polylines);
    return KanjiCheck(
      ok: matchingCandidate(target, guesses) != null && (grade?.ok ?? true),
      guesses: guesses,
      grade: grade,
    );
  }

  Future<void> close() => _recognizer.close();
}

/// Why a check failed, most specific first: a stroke problem names the
/// stroke; otherwise what the recogniser read.
String missMessage(KanjiCheck check) {
  final g = check.grade;
  final read = check.guesses.take(shownGuesses).join('、');
  if (g != null && !g.ok) {
    final i = (g.stroke ?? 0) + 1;
    return switch (g.issue!) {
      StrokeIssue.count => T.writingStrokeCount(g.drawn, g.expected),
      StrokeIssue.order => T.writingStrokeOrder(i, (g.expectedStroke ?? 0) + 1),
      StrokeIssue.direction => T.writingStrokeDirection(i),
      StrokeIssue.shape => T.writingStrokeShape(i),
    };
  }
  if (check.guesses.isEmpty) return T.writingNothingRead;
  return g != null ? T.writingShapeNotRead(read) : '${T.writingYouWrote} $read';
}
