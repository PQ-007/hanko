import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
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
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text(T.goalModalTitle),
            subtitle: Text(T.goalModalLabel),
            trailing: Text('${due?.newGoal ?? '—'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            onTap: () => showGoalDialog(context, ref, due?.newGoal ?? 20),
          ),
          ListTile(
            leading: SizedBox.square(dimension: 40, child: SpriteView(slug: hero, size: 40)),
            title: const Text(T.heroPickerTitle),
            subtitle: const Text(T.heroPickerHint),
            onTap: () => showHeroPicker(context),
          ),
          const Divider(),
          const ReminderTile(),
          const Divider(),
          if (Config.hasWebApi)
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text(T.privacy),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(Uri.parse('${Config.webApiBase}/privacy'),
                  mode: LaunchMode.externalApplication),
            ),
          ListTile(
            leading: const Icon(Icons.logout, color: HankoColors.inkSoft),
            title: const Text(T.signOut),
            subtitle: email == null ? null : Text(email),
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
    );
  }
}
