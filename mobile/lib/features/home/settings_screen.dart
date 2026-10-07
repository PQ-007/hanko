import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../social/social_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/theme_mode.dart';
import '../../core/widgets.dart';
import '../battle/hero.dart';
import '../battle/hero_picker.dart';
import '../battle/sprite_view.dart';
import '../settings/reminder_tile.dart';
import 'goal_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueSummaryProvider).value;
    final hero = ref.watch(heroProvider);
    final email = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      appBar: AppBar(title: const Text(T.settings)),
      body: ListView(
        children: [
          const _ProfileTile(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text(T.goalModalTitle),
            subtitle: Text(T.goalModalLabel),
            trailing: Text(
              '${due?.newGoal ?? '—'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            onTap: () => showGoalDialog(context, ref, due?.newGoal ?? 20),
          ),
          ListTile(
            leading: SizedBox.square(
              dimension: 48,
              child: SpriteView(slug: hero, size: 48),
            ),
            title: const Text(T.heroPickerTitle),
            subtitle: const Text(T.heroPickerHint),
            onTap: () => showHeroPicker(context),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text(T.appearance),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ThemePicker(
                value: ref.watch(themeModeProvider),
                onPick: (t) => ref.read(themeModeProvider.notifier).set(t),
              ),
            ),
          ),
          const Divider(),
          const ReminderTile(),
          const Divider(),
          // Friends see your daily numbers unless this is off (0026).
          ref
              .watch(myProfileProvider)
              .maybeWhen(
                data: (p) => SwitchListTile(
                  secondary: const Icon(Icons.visibility_outlined),
                  title: const Text(T.socialShareSetting),
                  subtitle: const Text(T.socialShareSettingDesc),
                  value: p.shareActivity,
                  onChanged: (v) async {
                    try {
                      await ref.read(socialApiProvider).setShare(v);
                    } catch (_) {}
                    ref.invalidate(myProfileProvider);
                    ref.invalidate(friendOverviewProvider);
                  },
                ),
                orElse: () => const SizedBox.shrink(),
              ),
          const Divider(),
          if (Config.privacyUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text(T.privacy),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(
                Uri.parse(Config.privacyUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ListTile(
            leading: Icon(Icons.logout, color: context.hk.inkSoft),
            title: const Text(T.signOut),
            subtitle: email == null ? null : Text(email),
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
    );
  }
}

/// Your picture and name at the top of Settings: change the photo (gallery,
/// shrunk by the picker before upload) or go back to the initial-letter one.
/// Friends see it on their lists; the web shows the same picture.
class _ProfileTile extends ConsumerStatefulWidget {
  const _ProfileTile();

  @override
  ConsumerState<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends ConsumerState<_ProfileTile> {
  bool _busy = false;

  Future<void> _change() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(socialApiProvider).setAvatar(await picked.readAsBytes());
      ref.invalidate(myProfileProvider);
      ref.invalidate(friendOverviewProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(T.avatarFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(socialApiProvider).removeAvatar();
      ref.invalidate(myProfileProvider);
      ref.invalidate(friendOverviewProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myProfileProvider).value;
    final name = me?.displayName ?? '?';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              UserAvatar(name: name, image: me?.image, radius: 34),
              if (_busy) const SizedBox.square(dimension: 68, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                if (me?.handle != null)
                  Text('@${me!.handle}', style: TextStyle(fontSize: 13, color: context.hk.inkMute)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _change,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text(T.avatarChange),
                    ),
                    if (me?.image != null)
                      TextButton(onPressed: _busy ? null : _remove, child: const Text(T.avatarRemove)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Three swatch tiles — the story images' styles as whole-app themes.
/// paper as whole-app themes.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.value, required this.onPick});
  final AppTheme value;
  final ValueChanged<AppTheme> onPick;

  static const _options = [
    (AppTheme.paper, T.themePaper),
    (AppTheme.dark, T.themeDark),
    (AppTheme.blue, T.themeBlue),
  ];

  @override
  Widget build(BuildContext context) {
    final hk = context.hk;
    return Row(
      children: [
        for (final (i, (t, label)) in _options.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: InkWell(
            onTap: () => onPick(t),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t == value ? hk.seal : hk.lineSoft, width: t == value ? 2 : 1),
              ),
              child: Column(
                children: [
                  _Swatch(theme: t),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: t == value ? FontWeight.w700 : FontWeight.w500,
                      color: t == value ? hk.ink : hk.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          )),
        ],
      ],
    );
  }
}

/// A tiny preview of a theme: its page colour with a card and an accent bar.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme});
  final AppTheme theme;

  Widget _half(HankoPalette p) => Container(
        color: p.paper,
        padding: const EdgeInsets.all(5),
        child: Container(
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(3)),
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(3),
          child: Container(height: 4, width: 14, color: p.seal),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 46,
        height: 34,
        child: _half(theme.palette),
      ),
    );
  }
}
