import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../writing/kanji_checker.dart' show handwritingModel, handwritingReady;
import '../writing/writing_pad.dart';

/// Draw one character, pick it from the candidates, draw the next — the
/// add-word sheet's search for kanji the user can read off a page but can't
/// type. The web's HandwritingPad.tsx, with ML Kit's on-device recogniser in
/// place of the web's remote one: the same model the writing lessons use,
/// downloaded once and then offline.
class HandwritingPad extends StatefulWidget {
  const HandwritingPad({super.key, required this.preContext, required this.onPick});

  /// Text before the caret, so the recogniser ranks by what makes a word.
  final String preContext;
  final ValueChanged<String> onPick;

  @override
  State<HandwritingPad> createState() => _HandwritingPadState();
}

enum _Model { checking, downloading, ready, failed }

class _HandwritingPadState extends State<HandwritingPad> {
  /// How long the pen has to rest before the ink is read.
  static const _settle = Duration(milliseconds: 300);

  /// Fixed slots, filled or not, so the panel keeps its shape between
  /// characters: two rows of five.
  static const _slots = 10;

  final _ink = <List<mlkit.StrokePoint>>[];
  final _recognizer = mlkit.DigitalInkRecognizer(languageCode: handwritingModel);
  var _model = _Model.checking;
  var _candidates = const <String>[];
  var _busy = false;
  Timer? _timer;
  Size _area = const Size(240, 240);

  /// Bumped whenever the ink changes, so a slow answer for older ink is dropped.
  var _seq = 0;

  @override
  void initState() {
    super.initState();
    _ensureModel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Fire-and-forget, so a failure here (no plugin, recogniser already gone)
    // must not surface as an uncaught error after the sheet has closed.
    _recognizer.close().catchError((_) {});
    super.dispose();
  }

  Future<void> _ensureModel() async {
    setState(() => _model = _Model.checking);
    if (await handwritingReady()) {
      if (mounted) setState(() => _model = _Model.ready);
      return;
    }
    if (mounted) setState(() => _model = _Model.downloading);
    final ok = await handwritingReady(download: true);
    if (!mounted) return;
    setState(() => _model = ok ? _Model.ready : _Model.failed);
    if (ok) _schedule();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void _start(Offset p) {
    setState(() => _ink.add([mlkit.StrokePoint(x: p.dx, y: p.dy, t: _now)]));
    _schedule();
  }

  void _update(Offset p) {
    if (_ink.isEmpty) return;
    setState(() => _ink.last.add(mlkit.StrokePoint(x: p.dx, y: p.dy, t: _now)));
    _schedule();
  }

  void _changed() {
    _seq++;
    _timer?.cancel();
    if (_ink.isEmpty) {
      _candidates = const [];
      _busy = false;
    } else {
      _schedule();
    }
  }

  void _schedule() {
    _seq++;
    _timer?.cancel();
    _timer = Timer(_settle, _recognize);
  }

  Future<void> _recognize() async {
    if (_ink.isEmpty || _model != _Model.ready) return;
    final mine = _seq;
    setState(() => _busy = true);
    List<String> out;
    try {
      final drawing = mlkit.Ink()..strokes = [for (final s in _ink) mlkit.Stroke()..points = [...s]];
      final result = await _recognizer.recognize(
        drawing,
        context: mlkit.DigitalInkRecognitionContext(
          preContext: widget.preContext,
          writingArea: mlkit.WritingArea(width: _area.width, height: _area.height),
        ),
      );
      out = [];
      for (final c in result) {
        final t = c.text.trim();
        if (t.isNotEmpty && !out.contains(t)) out.add(t);
        if (out.length == _slots) break;
      }
    } catch (_) {
      out = const [];
    }
    if (!mounted || mine != _seq) return;
    setState(() {
      _candidates = out;
      _busy = false;
    });
  }

  void _pick(String c) {
    widget.onPick(c);
    setState(() {
      _ink.clear();
      _changed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hk.paperDim.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hk.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) {
                    _area = box.biggest;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Claims the pointer on touch-down: a stroke drawn
                        // downwards would otherwise scroll or drag the sheet.
                        RawGestureDetector(
                          gestures: {
                            _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
                              _EagerPan.new,
                              (r) => r
                                ..onStart = ((d) => _start(d.localPosition))
                                ..onUpdate = ((d) => _update(d.localPosition)),
                            ),
                          },
                          child: WritingPad(
                            strokes: null,
                            guideCount: 0,
                            answer: false,
                            demo: false,
                            ink: _ink,
                            onStart: (_) {},
                            onUpdate: (_) {},
                          ),
                        ),
                        if (_ink.isEmpty)
                          IgnorePointer(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.draw_outlined, size: 22, color: hk.inkMute.withValues(alpha: 0.7)),
                                  const SizedBox(height: 4),
                                  Text(T.handwriteHint, style: TextStyle(fontSize: 12, color: hk.inkMute)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _status(hk),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var i = 0; i < _slots; i++)
                i < _candidates.length ? _candidate(hk, _candidates[i], first: i == 0) : _emptySlot(hk),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _ink.isEmpty
                      ? null
                      : () => setState(() {
                          _ink.removeLast();
                          _changed();
                        }),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text(T.writingUndo),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _ink.isEmpty
                      ? null
                      : () => setState(() {
                          _ink.clear();
                          _changed();
                        }),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text(T.writingClear),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _status(HankoPalette hk) {
    final (text, spin, error) = switch (_model) {
      _Model.checking => (T.handwritePick, true, false),
      _Model.downloading => (T.writingModelDownloading, true, false),
      _Model.failed => (T.writingModelFailed, false, true),
      _Model.ready => (T.handwritePick, _busy, false),
    };
    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: error ? Theme.of(context).colorScheme.error : hk.inkSoft,
            ),
          ),
        ),
        if (spin) ...[
          const SizedBox(width: 6),
          SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: hk.inkMute)),
        ],
        if (error)
          TextButton(onPressed: _ensureModel, child: const Text(T.retry)),
      ],
    );
  }

  Widget _candidate(HankoPalette hk, String c, {required bool first}) {
    return Material(
      color: first ? hk.sealTint : hk.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: first ? hk.seal : hk.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pick(c),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Text(
                c,
                style: TextStyle(fontSize: c.length > 1 ? 15 : 24, fontWeight: FontWeight.w500, color: hk.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptySlot(HankoPalette hk) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: hk.lineSoft),
    ),
  );
}

/// A pan that wins the gesture arena the moment a finger touches the pad,
/// so the sheet's scroll and drag-to-dismiss never see the stroke.
class _EagerPan extends PanGestureRecognizer {
  _EagerPan() : super(debugOwner: null);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
