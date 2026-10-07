import 'package:flutter/services.dart';

/// The home-screen icon follows the app theme: Цайвар's vermilion, Бараан's
/// charcoal or Цэнхэр's blue ensō (the same marks as the web's tab icons).
///
/// Native on both platforms, no package: Android enables one of three
/// launcher aliases (applied when the app goes to the background, see
/// MainActivity.kt); iOS sets an alternate icon (AppDelegate.swift), which
/// shows its own one-line notice. Best effort — a failure only means the old
/// icon stays, so it is never surfaced.
class AppIcon {
  const AppIcon._();

  static const _channel = MethodChannel('hanko/app_icon');

  /// [name] is an AppTheme name: paper, dark or blue.
  static Future<void> set(String name) async {
    try {
      await _channel.invokeMethod<void>('set', name);
    } catch (_) {}
  }
}
