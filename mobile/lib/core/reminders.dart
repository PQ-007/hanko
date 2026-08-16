import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'repository.dart';

/// A single daily "you have N cards due" reminder.
///
/// This is the largest retention lever the app has: an SRS tool you have to
/// remember to open is one you stop opening.
///
/// The count is genuinely accurate, not a guess. Rescheduling asks the server
/// what will be due *at the reminder's moment* (`due_summary(p_at)`), which
/// applies the same day cutoff and daily caps the review session does — so the
/// notification can't promise 47 cards and then hand you 20.
///
/// The number is a snapshot taken when the app was last open. Reviewing on the
/// web afterwards doesn't update it until the app is next foregrounded, which
/// is the honest limit of local scheduling — keeping it live would need a
/// background worker or push, and neither is worth it for a nudge.
class Reminders {
  Reminders(this._plugin, this._repo);

  final FlutterLocalNotificationsPlugin _plugin;
  final Repository _repo;

  static const _notificationId = 1001;
  static const _prefEnabled = 'reminder_enabled';
  static const _prefHour = 'reminder_hour';
  static const _prefMinute = 'reminder_minute';

  static const _defaultHour = 9;

  static Future<Reminders> create(Repository repo) async {
    tzdata.initializeTimeZones();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    return Reminders(plugin, repo);
  }

  Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_prefEnabled) ?? false;

  Future<({int hour, int minute})> time() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      hour: prefs.getInt(_prefHour) ?? _defaultHour,
      minute: prefs.getInt(_prefMinute) ?? 0,
    );
  }

  /// Android 13+ requires the user to grant notification permission explicitly;
  /// without this the schedule call silently succeeds and nothing ever appears.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, false);
    await _plugin.cancel(id: _notificationId);
  }

  Future<void> enable({int? hour, int? minute}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, true);
    if (hour != null) await prefs.setInt(_prefHour, hour);
    if (minute != null) await prefs.setInt(_prefMinute, minute);
    await reschedule();
  }

  /// Safe to call on every app start: it cancels and re-creates the pending
  /// notification with a fresh count.
  Future<void> reschedule() async {
    if (!await isEnabled()) return;

    final t = await time();
    final when = _nextOccurrence(t.hour, t.minute);

    int dueThen;
    try {
      final summary = await _repo.dueSummary(at: when.toUtc());
      dueThen = summary.dueNow;
    } catch (e) {
      debugPrint('Reminder: could not forecast due count: $e');
      return;
    }

    await _plugin.cancel(id: _notificationId);

    // Nothing to review is not worth a notification. Skipping the schedule
    // entirely is better than a reminder that says "0 cards".
    if (dueThen <= 0) return;

    await _plugin.zonedSchedule(
      id: _notificationId,
      title: 'Hanko',
      body: '$dueThen үг давтахад бэлэн байна',
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_review',
          'Өдөр тутмын сануулга',
          channelDescription: 'Давтах үг байгаа эсэхийг сануулна',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }
}
