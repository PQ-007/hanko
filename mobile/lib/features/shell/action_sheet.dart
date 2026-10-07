import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../review/review_mode_sheet.dart';
import 'quick_add_sheet.dart';

enum _Action { review, addWord, scan, audioDeck }

/// The center button's sheet: the app's four primary actions in one place.
Future<void> showActionSheet(BuildContext context, WidgetRef ref) async {
  final action = await showModalBottomSheet<_Action>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _Tile(
            icon: Icons.play_circle_outline,
            label: T.actionStartReview,
            primary: true,
            onTap: () => Navigator.of(ctx).pop(_Action.review),
          ),
          _Tile(
            icon: Icons.add_circle_outline,
            label: T.actionAddWord,
            onTap: () => Navigator.of(ctx).pop(_Action.addWord),
          ),
          _Tile(
            icon: Icons.document_scanner_outlined,
            label: T.actionScan,
            onTap: () => Navigator.of(ctx).pop(_Action.scan),
          ),
          _Tile(
            icon: Icons.headphones_outlined,
            label: T.actionAudioDeck,
            onTap: () => Navigator.of(ctx).pop(_Action.audioDeck),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _Action.review:
      await startReviewFlow(context, ref);
    case _Action.addWord:
      await showQuickAddSheet(context, ref);
    case _Action.scan:
      await context.push(Routes.capture);
      ref.refreshLibrary();
    case _Action.audioDeck:
      await context.push(Routes.audio);
  }
}

/// Opens the mode picker, runs the chosen session full-screen, then refreshes
/// everything a session can change.
Future<void> startReviewFlow(BuildContext context, WidgetRef ref, {String? deckId}) async {
  final route = await showReviewModeSheet(context, deckId: deckId);
  if (route == null || !context.mounted) return;
  await context.push(route);
  ref.refreshAfterReview();
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = primary ? Colors.white : (enabled ? context.hk.ink : context.hk.inkMute);
    return Material(
      color: primary ? context.hk.seal : context.hk.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: primary ? BorderSide.none : BorderSide(color: context.hk.lineSoft),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: primary ? Colors.white : (enabled ? context.hk.seal : context.hk.line)),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
