import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'ical.dart';
import 'notifications.dart';
import 'store.dart';
import 'task.dart';

const _taskName = 'brone-sync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    // Isolate latar belakang perlu mendaftarkan plugin Dart sendiri.
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();
    await Notifications.init();
    await SyncService.run();
    return true;
  });
}

class SyncService {
  static Future<void> registerBackground() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> run() async {
    final store = Store();
    final url = await store.calendarUrl();
    if (url != null) {
      try {
        final events = await fetchCalendar(url);
        final tasks = mergeFeed(
          await store.loadTasks(),
          events,
          DateTime.now().millisecondsSinceEpoch,
        );
        await store.saveTasks(tasks);
        await store.markSynced(DateTime.now().millisecondsSinceEpoch);
      } on BroneException catch (e) {
        await store.markFailed(e.message);
      }
    }
    await refreshReminders(store);
  }

  static Future<void> refreshReminders(Store store) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tasks = await store.loadTasks();
    await Notifications.announce(tasks, now);
    await store.saveTasks(tasks);
    await Notifications.reschedule(tasks, now);
  }
}
