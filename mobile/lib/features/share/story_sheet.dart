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

  Future<void> _render() async {
    final card = _card;
    if (card == null) return;
    final id = ++_renderId;
    final size = _size;
    try {
      final png = await renderStoryCard(card, size, _style, _lang);
      if (mounted && id == _renderId) setState(() => _png = png);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _pick({StoryStyle? style, StoryLang? lang}) async {
    setState(() {
      _style = style ?? _style;
      _lang = lang ?? _lang;
    });
    _render();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_optsStyle, _style.name);
      await prefs.setString(_optsLang, _lang.name);
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
