import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_icon.dart';
import 'theme.dart';

const _key = 'hanko.themeMode';

/// The app's look: the same three styles as the story images — Цайвар (warm
/// amber paper, white cards, vermilion seal; the default), Бараан and Цэнхэр.
/// Per device, like the hero choice. No "follow the phone" option, on
/// purpose. Older stored values (system, light) land on Цайвар.
enum AppTheme {
  paper,
  dark,
  blue;

  ThemeMode get mode => this == AppTheme.paper ? ThemeMode.light : ThemeMode.dark;

  HankoPalette get palette => switch (this) {
        AppTheme.paper => HankoPalette.paperTheme,
        AppTheme.dark => HankoPalette.dark,
        AppTheme.blue => HankoPalette.blue,
      };
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppTheme>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<AppTheme> {
  @override
  AppTheme build() {
    _load();
    return AppTheme.paper;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      final t = AppTheme.values.asNameMap()[stored];
      if (t != null) state = t;
      // Keeps the home-screen icon in step (a no-op when it already is).
      AppIcon.set(state.name);
    } catch (_) {}
  }

  Future<void> set(AppTheme t) async {
    state = t;
    AppIcon.set(t.name);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, t.name);
    } catch (_) {}
  }
}
