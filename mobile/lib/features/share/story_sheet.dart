import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import 'story_card.dart';

/// A story card's preview, its style and meaning-language pickers, and Share
/// (the phone's share sheet — Instagram, Facebook, Messenger, Save to
/// Photos…). Same panel as the web's StoryImagePanel.
///
/// [card] is loaded by the caller; it resolves to null when there is nothing
/// to show ([emptyText]) and throws when loading failed.
Future<void> showStorySheet(
  BuildContext context, {
  required String title,
  required Future<StoryCard?> card,
  required String fileName,
  String emptyText = T.shareTodayEmpty,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StorySheet(title: title, card: card, fileName: fileName, emptyText: emptyText),
    );

const _optsStyle = 'hanko.story.style';
const _optsLang = 'hanko.story.lang';
const _optsLayout = 'hanko.story.layout';

class _StorySheet extends StatefulWidget {
  const _StorySheet({required this.title, required this.card, required this.fileName, required this.emptyText});
  final String title;
  final Future<StoryCard?> card;
  final String fileName;
  final String emptyText;

  @override
  State<_StorySheet> createState() => _StorySheetState();
}

class _StorySheetState extends State<_StorySheet> {
  StoryStyle _style = StoryStyle.seal;
  StoryLang _lang = StoryLang.mn;
  StoryLayout _layout = StoryLayout.grid;

  /// Which word Spotlight/Quiz show (and the quiz's answer slot): "another word".
  int _seed = 0;
  StoryCard? _card;
  bool _loading = true;
  bool _failed = false;
  Uint8List? _png;
  int _renderId = 0;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Style and meaning language, remembered per device (like the web's
    // hanko.story.opts).
    try {
      final prefs = await SharedPreferences.getInstance();
      _style = StoryStyle.values.asNameMap()[prefs.getString(_optsStyle)] ?? _style;
      _lang = StoryLang.values.asNameMap()[prefs.getString(_optsLang)] ?? _lang;
      _layout = StoryLayout.values.asNameMap()[prefs.getString(_optsLayout)] ?? _layout;
    } catch (_) {}
    try {
      _card = await widget.card;
    } catch (_) {
      _failed = true;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _render();
  }

  ui.Size get _size => storySize(MediaQuery.of(context).size);

  bool get _quizOk => _card != null && buildStoryQuiz(_card!.words, _lang, 0) != null;

  /// The layout actually drawn: Quiz falls back to Grid when there aren't
  /// four words with meanings.
  StoryLayout get _drawn => _layout == StoryLayout.quiz && !_quizOk ? StoryLayout.grid : _layout;

  Future<void> _render() async {
    final card = _card;
    if (card == null) return;
    final id = ++_renderId;
    final size = _size;
    try {
      final png = await renderStoryCard(card, size, _style, _lang, layout: _drawn, seed: _seed);
      if (mounted && id == _renderId) setState(() => _png = png);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _pick({StoryStyle? style, StoryLang? lang, StoryLayout? layout}) async {
    setState(() {
      _style = style ?? _style;
      _lang = lang ?? _lang;
      _layout = layout ?? _layout;
    });
    _render();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_optsStyle, _style.name);
      await prefs.setString(_optsLang, _lang.name);
      await prefs.setString(_optsLayout, _layout.name);
    } catch (_) {}
  }

  Future<void> _share() async {
    final png = _png;
    if (png == null) return;
    setState(() => _sharing = true);
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: '${widget.fileName}.png')],
        fileNameOverrides: ['${widget.fileName}.png'],
      ));
    } catch (_) {
      // Dismissed, or the target refused the file — nothing to report.
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final size = _size;
    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    } else if (_failed) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(T.loadFailed, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700)),
      );
    } else if (_card == null) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(widget.emptyText, textAlign: TextAlign.center, style: TextStyle(color: hk.inkSoft)),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 190,
              height: 190 * size.height / size.width,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: hk.paperDim,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: hk.line),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: _png == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : Image.memory(_png!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          const SizedBox(height: 16),
          Text(T.storyLayoutLabel,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: hk.inkSoft)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (i, (l, label)) in const [
                (StoryLayout.grid, T.storyLayoutGrid),
                (StoryLayout.list, T.storyLayoutList),
                (StoryLayout.spotlight, T.storyLayoutSpotlight),
                (StoryLayout.quiz, T.storyLayoutQuiz),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _LayoutTile(
                    layout: l,
                    label: label,
                    selected: _drawn == l,
                    enabled: l != StoryLayout.quiz || _quizOk,
                    onTap: () => _pick(layout: l),
                  ),
                ),
              ],
            ],
          ),
          if (_layout == StoryLayout.quiz && !_quizOk)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(T.storyQuizNeedsWords,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: hk.inkMute)),
            ),
          if ((_drawn == StoryLayout.spotlight || _drawn == StoryLayout.quiz) && _card!.words.length > 1)
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(T.storyNextWord),
                style: TextButton.styleFrom(foregroundColor: hk.sealText),
                onPressed: () {
                  setState(() => _seed++);
                  _render();
                },
              ),
            ),
          const SizedBox(height: 10),
          _Row(
            label: T.storyStyleLabel,
            child: Wrap(
              spacing: 6,
              children: [
                for (final (s, label, swatch) in [
                  (StoryStyle.seal, T.storyStyleSeal, const [Color(0xFF2C72CC), Color(0xFF0F3672)]),
                  (StoryStyle.dark, T.storyStyleDark, const [Color(0xFF14181E), Color(0xFF14181E)]),
                  (StoryStyle.paper, T.storyStylePaper, const [Color(0xFFC8442F), Color(0xFFF8F2E6)]),
                ])
                  ChoiceChip(
                    selected: _style == s,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    avatar: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x22000000)),
                        gradient: s == StoryStyle.paper
                            ? RadialGradient(colors: swatch, stops: const [0.4, 0.5])
                            : LinearGradient(
                                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: swatch),
                      ),
                    ),
                    label: Text(label),
                    onSelected: (_) => _pick(style: s),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Row(
            label: T.storyLangLabel,
            child: SegmentedButton<StoryLang>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: StoryLang.mn, label: Text(T.storyLangMn)),
                ButtonSegment(value: StoryLang.en, label: Text(T.storyLangEn)),
                ButtonSegment(value: StoryLang.both, label: Text(T.storyLangBoth)),
              ],
              selected: {_lang},
              onSelectionChanged: (v) => _pick(lang: v.first),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            T.shareImageHint(size.width.round(), size.height.round()),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: hk.inkMute),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text(T.shareImageShare),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _png == null || _sharing ? null : _share,
          ),
        ],
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            body,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.hk.inkSoft)),
        const SizedBox(width: 12),
        Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
      ],
    );
  }
}

/// One layout choice: a tiny drawing of the layout and its name.
class _LayoutTile extends StatelessWidget {
  const _LayoutTile({
    required this.layout,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final StoryLayout layout;
  final String label;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final fg = selected ? hk.ink : hk.inkSoft;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? hk.sealTint : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? hk.seal : hk.line),
          ),
          child: Column(
            children: [
              CustomPaint(size: const Size(16, 24), painter: _GlyphPainter(layout, fg)),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same little layout drawings as the web picker (StoryImagePanel).
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.layout, this.color);
  final StoryLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 18, size.height / 28);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint()..color = color.withValues(alpha: 0.6);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.5, 0.5, 17, 27), const Radius.circular(3)), line);
    void box(double x, double y, double w, double h) =>
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(1)), fill);
    switch (layout) {
      case StoryLayout.grid:
        for (final y in [6.0, 13.0, 20.0]) {
          box(3, y, 5.5, 5);
          box(9.5, y, 5.5, 5);
        }
      case StoryLayout.list:
        for (final y in [6.0, 11.0, 16.0, 21.0]) {
          box(3, y, 12, 3.5);
        }
      case StoryLayout.spotlight:
        box(3, 8, 12, 13);
      case StoryLayout.quiz:
        box(3, 4, 12, 7);
        for (final y in [13.0, 16.5, 20.0, 23.5]) {
          box(3, y, 12, 2.3);
        }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.layout != layout || old.color != color;
}
