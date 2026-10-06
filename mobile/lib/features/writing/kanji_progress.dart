import 'package:shared_preferences/shared_preferences.dart';

import '../social/social_api.dart';

/// Kanji the learner has written from memory in a lesson. Lessons skip the
/// trace/partial/blank ladder for these, and the setup screen marks them.
///
/// Kept on the phone for speed and offline lessons, and on the server
/// (`learned_kanji`, 0026) so they survive a reinstall, follow you to another
/// phone, earn XP and show to friends. [syncLearnedKanji] merges the two.
const _key = 'hanko.writing.learned';

Future<Set<String>> loadLearnedKanji() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  } catch (_) {
    return {};
  }
}

Future<void> saveLearnedKanji(Set<String> kanji) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, kanji.toList());
  } catch (_) {}
}

/// Local and server sets merged: local-only kanji (learned offline, or before
/// the server kept them) are uploaded, server-only ones come down. Offline or
/// without the 0026 migration it's simply the local set.
Future<Set<String>> syncLearnedKanji(SocialApi api) async {
  final local = await loadLearnedKanji();
  try {
    final server = await api.learnedKanji();
    final missing = local.difference(server);
    if (missing.isNotEmpty) await api.addLearnedKanji(missing);
    final all = {...local, ...server};
    if (all.length != local.length) await saveLearnedKanji(all);
    return all;
  } catch (_) {
    return local;
  }
}
