import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task.dart';

/// Link kalender bersifat rahasia, jadi disimpan di Android Keystore.
class Store {
  static const _secure = FlutterSecureStorage();
  static const _urlKey = 'brone_calendar_url';
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<List<Task>> loadTasks() async {
    final raw = await _prefs.getString('tasks');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveTasks(List<Task> tasks) => _prefs.setString(
    'tasks',
    jsonEncode(tasks.map((t) => t.toJson()).toList()),
  );

  Future<String?> calendarUrl() => _secure.read(key: _urlKey);
  Future<void> setCalendarUrl(String url) =>
      _secure.write(key: _urlKey, value: url);
  Future<void> clearCalendarUrl() async {
    await _secure.delete(key: _urlKey);
    await _prefs.remove('lastError');
  }

  Future<int?> lastSync() => _prefs.getInt('lastSync');
  Future<String?> lastError() => _prefs.getString('lastError');

  Future<void> markSynced(int now) async {
    await _prefs.setInt('lastSync', now);
    await _prefs.remove('lastError');
  }

  Future<void> markFailed(String message) =>
      _prefs.setString('lastError', message);
}
