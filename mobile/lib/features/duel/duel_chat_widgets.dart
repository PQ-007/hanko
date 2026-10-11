import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../battle/sprite_data.dart';
import '../battle/sprite_view.dart';
import 'duel_chat.dart';
import 'duel_chat_rules.dart';

const _paper = Color(0xFFFAF7F0);

/// A fighter that can be talked through: plays an emote's pose on its own
/// sprite and settles back to [base], with the latest message in a speech
/// bubble above it (web: ChatFighter.tsx). Ready room and result screen.
class ChatFighter extends StatefulWidget {
  const ChatFighter({
    super.key,
    required this.slug,
    required this.base,
    required this.beat,
    this.flip = false,
    this.size = 120,
  });

  final String slug;
  final String base;
  final ChatBeat? beat;
  final bool flip;
  final double size;

  @override
  State<ChatFighter> createState() => _ChatFighterState();
}

class _ChatFighterState extends State<ChatFighter> {
  /// How long an emote's pose holds, and how long a bubble stays up.
  static const _poseFor = Duration(milliseconds: 1200);
  static const _bubbleFor = Duration(milliseconds: 3200);

  String? _pose;
  ChatBeat? _bubble;
  Timer? _settle, _hide;

  @override
  void didUpdateWidget(ChatFighter old) {
    super.didUpdateWidget(old);
    final b = widget.beat;
    if (b == null || b.nonce == old.beat?.nonce) return;
    _settle?.cancel();
    _hide?.cancel();
    final available = spriteFrames[widget.slug]?.keys ?? const <String>[];
    setState(() {
      _bubble = b;
      _pose = b.emote == null ? null : emotePose(available, b.emote!);
    });
    _settle = Timer(_poseFor, () {
      if (mounted) setState(() => _pose = null);
    });
    _hide = Timer(_bubbleFor, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _bubble;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SpriteView(
            slug: widget.slug,
            state: _pose ?? widget.base,
            size: widget.size,
            flip: widget.flip,
            // A new beat replays the clip from frame one, even the same emote twice.
            replayKey: _pose == null ? 0 : (b?.nonce ?? 0),
          ),
          if (b != null)
            Positioned(
              top: -8,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.size + 40),
                child: _Bubble(text: b.text, big: b.emote != null),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.big});
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF18181B),
                fontSize: big ? 22 : 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          CustomPaint(size: const Size(12, 6), painter: _Tail()),
        ],
      ),
    );
  }
}

class _Tail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// The chat under the fighters: a short log, emotes, preset phrases, and a
/// text box for a friend only (web: DuelChatPanel.tsx).
class DuelChatPanel extends StatefulWidget {
  const DuelChatPanel({super.key, required this.chat, required this.foeName});
  final DuelChat chat;
  final String foeName;

  @override
  State<DuelChatPanel> createState() => _DuelChatPanelState();
}

class _DuelChatPanelState extends State<DuelChatPanel> {
  final _draft = TextEditingController();
  final _log = ScrollController();

  @override
  void dispose() {
    _draft.dispose();
    _log.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.chat.send(ChatKind.text, _draft.text)) {
      _draft.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    // Newest at the bottom, kept in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_log.hasClients) _log.jumpTo(_log.position.maxScrollExtent);
    });
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 92,
            child: chat.entries.isEmpty
                ? Center(
                    child: Text(T.duelChatEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _paper.withValues(alpha: 0.4), fontSize: 12)),
                  )
                : ListView(
                    controller: _log,
                    children: [
                      for (final e in chat.entries)
                        Align(
                          alignment: e.mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: '${e.mine ? T.duelYou : widget.foeName} ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: e.mine ? const Color(0xFF7DD3FC) : const Color(0xFFFDA4AF),
                                  ),
                                ),
                                TextSpan(
                                  text: e.text,
                                  style: TextStyle(
                                    color: _paper.withValues(alpha: 0.9),
                                    fontSize: e.kind == ChatKind.emote ? 18 : 14,
                                  ),
                                ),
                              ]),
                              textAlign: e.mine ? TextAlign.right : TextAlign.left,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in emotes)
                Material(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => chat.send(ChatKind.emote, e.id),
                    child: SizedBox.square(
                      dimension: 42,
                      child: Center(child: Text(e.icon, style: const TextStyle(fontSize: 21))),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in phrases.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: OutlinedButton(
                      onPressed: () => chat.send(ChatKind.phrase, p.key),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _paper.withValues(alpha: 0.85),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                        shape: const StadiumBorder(),
                      ),
                      child: Text(p.value, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (chat.canType)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    maxLength: maxChatText,
                    style: const TextStyle(color: _paper, fontSize: 14),
                    textInputAction: TextInputAction.send,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      hintText: T.duelChatPlaceholder,
                      hintStyle: TextStyle(color: _paper.withValues(alpha: 0.35)),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.2),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _draft.text.trim().isEmpty ? null : _submit,
                  child: const Text(T.duelChatSend),
                ),
              ],
            )
          else
            Text(T.duelChatStrangers,
                textAlign: TextAlign.center,
                style: TextStyle(color: _paper.withValues(alpha: 0.4), fontSize: 11)),
        ],
      ),
    );
  }
}
