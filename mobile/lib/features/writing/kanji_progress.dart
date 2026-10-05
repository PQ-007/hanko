import 'package:shared_preferences/shared_preferences.dart';

/// Kanji the learner has written from memory in a lesson, kept on this phone.
/// Lessons skip the trace/partial/blank ladder for these, and the setup
/// screen marks them. Per device on purpose: it's a convenience for pacing
/// lessons, not review history, which lives in `review_log`.
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
