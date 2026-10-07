import 'package:flutter/material.dart';

import 'strings.dart';
import 'theme.dart';

/// The app's own confirm dialog, in place of a bare AlertDialog — same look
/// as the web's (`web/src/ui/Dialog.tsx`): an icon badge, a title, the
/// explanation, and a destructive action that is unmistakably red.
///
/// Resolves to true only when the confirm button is pressed; dismissing it
/// (scrim tap, back gesture, cancel) is false.
Future<bool> askConfirm(
  BuildContext context, {
  required String title,
  String? body,
  String? confirmLabel,
  String? cancelLabel,
  bool danger = false,
  IconData? icon,
}) async {
  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelLabel ?? T.cancel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => _ConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel ?? (danger ? T.delete : T.ok),
      cancelLabel: cancelLabel ?? T.cancel,
      danger: danger,
      icon: icon ?? (danger ? Icons.delete_outline_rounded : null),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
  return ok == true;
}

const _danger = Color(0xFFDC2626);

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.danger,
    required this.icon,
  });

  final String title;
  final String? body;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    final accent = danger ? _danger : context.hk.seal;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Material(
              color: hk.card,
              elevation: 12,
              shadowColor: Colors.black54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: hk.line),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (icon != null)
                      Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: accent, size: 26),
                        ),
                      ),
                    if (icon != null) const SizedBox(height: 14),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: hk.ink,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        body!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, height: 1.45, color: hk.inkSoft),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(confirmLabel),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: hk.inkSoft,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(cancelLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of [showActionSheet].
class SheetAction {
  const SheetAction(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// The long-press menu: a bottom sheet titled with what was pressed, its
/// actions below, the destructive one last and in red.
Future<void> showActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<SheetAction> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final hk = ctx.hk;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: hk.ink),
                    ),
                    if (subtitle != null)
                      Text(subtitle, style: TextStyle(fontSize: 12, color: hk.inkMute)),
                  ],
                ),
              ),
              for (final (i, a) in actions.indexed) ...[
                if (a.danger && i > 0) Divider(height: 12, color: hk.lineSoft),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(a.icon, color: a.danger ? _danger : hk.inkSoft),
                  title: Text(
                    a.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: a.danger ? _danger : hk.ink,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    a.onTap();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
