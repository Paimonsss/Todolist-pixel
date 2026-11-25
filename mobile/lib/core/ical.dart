import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'task.dart';

class BroneException implements Exception {
  BroneException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _wibOffsetMs = 7 * 3600000;

String _unescape(String v) => v
    .replaceAll(RegExp(r'\\n', caseSensitive: false), '\n')
    .replaceAllMapped(RegExp(r'\\([,;\\])'), (m) => m[1]!)
    .trim();

/// Waktu tanpa zona dianggap WIB. Acara sehari penuh bertenggat 23:59 WIB.
int? parseIcalDate(String value) {
  final m = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$',
  ).firstMatch(value.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (m[4] == null) {
    return DateTime.utc(y, mo, d, 23, 59).millisecondsSinceEpoch - _wibOffsetMs;
  }
  final ms = DateTime.utc(
    y,
    mo,
    d,
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  ).millisecondsSinceEpoch;
  return m[7] != null ? ms : ms - _wibOffsetMs;
}

bool isOpeningEvent(String summary) => RegExp(
  r'(\bopens|\bis open|\bdibuka|\bmulai)\s*\)?\s*$',
  caseSensitive: false,
).hasMatch(summary);

List<CalendarEvent> parseCalendar(String text) {
  if (!text.contains('BEGIN:VCALENDAR')) {
    throw BroneException(
      'Respons BRONE bukan kalender. Hubungkan ulang akunmu.',
    );
  }
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '')
      .split('\n');
  final events = <CalendarEvent>[];
  Map<String, String>? cur;

  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      cur = {};
    } else if (line == 'END:VEVENT') {
      final c = cur;
      cur = null;
      if (c == null) continue;
      final due = parseIcalDate(c['DTSTART'] ?? '');
      final uid = c['UID'], title = c['SUMMARY'];
      if (uid != null &&
          title != null &&
          title.isNotEmpty &&
          due != null &&
          !isOpeningEvent(title)) {
        events.add(
          CalendarEvent(
            uid: uid,
            title: title,
            dueAt: due,
            course: c['CATEGORIES'] ?? '',
          ),
        );
      }
    } else if (cur != null) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).split(';').first.toUpperCase();
      final value = line.substring(colon + 1);
      if (key == 'UID' || key == 'DTSTART') cur[key] = value.trim();
      if (key == 'SUMMARY' || key == 'CATEGORIES') cur[key] = _unescape(value);
    }
  }
  return events;
}

/// Hanya menerima link ekspor kalender BRONE, lalu memaksa rentang semua acara mendatang.
String normalizeBroneUrl(String input) {
  final url = Uri.tryParse(input.trim());
  if (url == null ||
      url.scheme != 'https' ||
      url.host != 'brone.ub.ac.id' ||
      url.hasPort ||
      url.userInfo.isNotEmpty ||
      url.path != '/calendar/export_execute.php') {
    throw BroneException('Gunakan link dari halaman Export calendar BRONE.');
  }
  final q = Map<String, String>.of(url.queryParameters);
  if ((q['userid'] ?? '').isEmpty || (q['authtoken'] ?? '').isEmpty) {
    throw BroneException('Link belum lengkap. Salin seluruh link kalendernya.');
  }
  q['preset_what'] = 'all';
  q['preset_time'] = 'recentupcoming';
  return url.replace(queryParameters: q).toString();
}

Future<List<CalendarEvent>> fetchCalendar(
  String calendarUrl, {
  http.Client? client,
}) async {
  final url = Uri.parse(normalizeBroneUrl(calendarUrl));
  final c = client ?? http.Client();
  Object lastError = BroneException('Gagal menghubungi BRONE.');
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final req = http.Request('GET', url)
          ..followRedirects = false
          ..headers['accept'] = 'text/calendar,text/plain;q=0.9';
        final res = await c.send(req).timeout(const Duration(seconds: 20));
        if (res.statusCode >= 300 && res.statusCode < 400) {
          throw BroneException(
            'BRONE meminta login lagi. Hubungkan ulang akunmu.',
          );
        }
        if (res.statusCode != 200) {
          throw BroneException('BRONE membalas status ${res.statusCode}.');
        }
        final bytes = await res.stream.toBytes().timeout(
          const Duration(seconds: 20),
        );
        if (bytes.length > 5000000)
          throw BroneException('Kalender terlalu besar.');
        return parseCalendar(utf8.decode(bytes, allowMalformed: true));
      } on BroneException catch (e) {
        lastError = e;
        if (!e.message.startsWith('BRONE membalas')) break;
      } on TimeoutException {
        lastError = BroneException('BRONE terlalu lama merespons.');
      } on http.ClientException {
        lastError = BroneException('Tidak bisa terhubung ke BRONE.');
      } on Exception {
        lastError = BroneException('Tidak bisa terhubung ke BRONE.');
      }
    }
  } finally {
    if (client == null) c.close();
  }
  throw lastError;
}
