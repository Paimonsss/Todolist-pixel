import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'task.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _hours = [72, 24, 6, 1];
  static const _maxScheduled =
      200; // Android membatasi jumlah alarm per aplikasi.

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static Future<void> init() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notif'),
      ),
    );
  }

  static Future<bool> enabled() async =>
      await _android?.areNotificationsEnabled() ?? false;
  static Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  static NotificationDetails _details(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'tenggat_tugas',
      'Tenggat tugas',
      channelDescription: 'Tugas baru dan pengingat tenggat',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      styleInformation: BigTextStyleInformation(body),
    ),
  );

  static int _stableId(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return 100000 + h % 1000000;
  }

  static String _label(int h) => switch (h) {
    1 => 'Sisa 1 jam!',
    6 => 'Sisa 6 jam!',
    24 => 'Besok tenggat!',
    _ => 'Sisa 3 hari',
  };

  static Future<void> show(String title, String body, {int id = 1}) =>
      _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details(body),
      );

  /// Mengumumkan tugas baru. Jika izin belum ada, tugas tetap menunggu diumumkan.
  static Future<void> announce(List<Task> tasks, int now) async {
    final fresh =
        tasks.where((t) => !t.done && t.dueAt > now && !t.announced).toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (fresh.isEmpty || !await enabled()) return;

    if (fresh.length > 3) {
      await show(
        '${fresh.length} tugas baru dari BRONE',
        'Terdekat: ${fresh.first.title}',
      );
    } else {
      for (final t in fresh) {
        await show(
          t.dueChanged ? 'Tenggat berubah' : 'Tugas baru',
          '${t.title}\n${formatDue(t.dueAt)}',
          id: _stableId(t.id),
        );
      }
    }
    for (final t in fresh) {
      t.announced = true;
      t.dueChanged = false;
    }
  }

  /// Menyusun ulang semua pengingat, sehingga tugas selesai otomatis berhenti diingatkan.
  static Future<void> reschedule(List<Task> tasks, int now) async {
    await _plugin.cancelAllPendingNotifications();
    final plan = <({int at, Task task, int hours})>[];
    for (final t in tasks.where((t) => !t.done && t.dueAt > now)) {
      for (final h in _hours) {
        final at = t.dueAt - h * 3600000;
        if (at > now + 5000) plan.add((at: at, task: t, hours: h));
      }
    }
    plan.sort((a, b) => a.at.compareTo(b.at));

    var id = 1000;
    for (final p in plan.take(_maxScheduled)) {
      final body = '${p.task.title}\n${formatDue(p.task.dueAt)}';
      await _plugin.zonedSchedule(
        id: id++,
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, p.at),
        title: _label(p.hours),
        body: body,
        notificationDetails: _details(body),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
