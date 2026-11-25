import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tugas_quest/core/ical.dart';
import 'package:tugas_quest/core/task.dart';
import 'package:tugas_quest/ui/pixel.dart';

const hour = 3600000;
const ics =
    'BEGIN:VCALENDAR\r\n'
    'BEGIN:VEVENT\r\nUID:1@brone\r\nSUMMARY:Laporan Praktikum\\, Bab 2\r\n  is due\r\nCATEGORIES:PBO-A\r\nDTSTART:20261201T100000Z\r\nEND:VEVENT\r\n'
    'BEGIN:VEVENT\r\nUID:2@brone\r\nSUMMARY:Kuis 1 opens\r\nDTSTART:20261201T100000Z\r\nEND:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  test('parseCalendar mengambil tugas dan membuang acara dibuka', () {
    final events = parseCalendar(ics);
    expect(events, hasLength(1));
    expect(events.first.title, 'Laporan Praktikum, Bab 2 is due');
    expect(events.first.course, 'PBO-A');
    expect(
      events.first.dueAt,
      DateTime.utc(2026, 12, 1, 10).millisecondsSinceEpoch,
    );
  });

  test('halaman non-kalender ditolak', () {
    expect(
      () => parseCalendar('<html>login</html>'),
      throwsA(isA<BroneException>()),
    );
  });

  test('waktu tanpa zona dibaca sebagai WIB', () {
    expect(
      parseIcalDate('20261201T170000'),
      DateTime.utc(2026, 12, 1, 10).millisecondsSinceEpoch,
    );
  });

  test('hanya link kalender BRONE yang diterima', () {
    final ok = normalizeBroneUrl(
      'https://brone.ub.ac.id/calendar/export_execute.php?userid=5&authtoken=abc&preset_what=user&preset_time=weeknow',
    );
    expect(ok, contains('preset_what=all'));
    expect(ok, contains('preset_time=recentupcoming'));
    for (final bad in [
      'http://brone.ub.ac.id/calendar/export_execute.php?userid=5&authtoken=abc',
      'https://brone.ub.ac.id.evil.test/calendar/export_execute.php?userid=5&authtoken=abc',
      'https://user@brone.ub.ac.id/calendar/export_execute.php?userid=5&authtoken=abc',
      'https://brone.ub.ac.id/login/index.php?userid=5&authtoken=abc',
      'https://brone.ub.ac.id/calendar/export_execute.php?userid=5',
    ]) {
      expect(
        () => normalizeBroneUrl(bad),
        throwsA(isA<BroneException>()),
        reason: bad,
      );
    }
  });

  test(
    'mergeFeed menambah, memperbarui tenggat, dan menghapus tugas hilang',
    () {
      const now = 1000;
      var tasks = mergeFeed([], [
        CalendarEvent(uid: 'a', title: 'A', dueAt: now + hour),
        CalendarEvent(uid: 'b', title: 'B', dueAt: now + hour),
        CalendarEvent(uid: 'old', title: 'Lama', dueAt: now - 1),
      ], now);
      expect(tasks, hasLength(2));
      tasks.first.announced = true;
      tasks = mergeFeed(tasks, [
        CalendarEvent(uid: 'a', title: 'A', dueAt: now + 2 * hour),
      ], now);
      expect(tasks, hasLength(1));
      expect(tasks.first.announced, isFalse);
      expect(tasks.first.dueChanged, isTrue);
    },
  );

  test('tugas selesai tetap selesai setelah sinkron', () {
    const now = 1000;
    final task = Task(
      id: 'b:a',
      source: 'brone',
      uid: 'a',
      title: 'A',
      dueAt: now + hour,
      done: true,
    );
    final tasks = mergeFeed(
      [task],
      [CalendarEvent(uid: 'a', title: 'A baru', dueAt: now + hour)],
      now,
    );
    expect(tasks.single.done, isTrue);
    expect(tasks.single.title, 'A baru');
  });

  test('tugas yang sudah dikumpulkan otomatis selesai', () {
    Task brone(String uid, {bool keepOpen = false}) => Task(
      id: 'b:$uid',
      source: 'brone',
      uid: uid,
      title: uid,
      dueAt: hour,
      keepOpen: keepOpen,
    );
    final tasks = [
      brone('11@brone.ub.ac.id'),
      brone('12@brone.ub.ac.id'),
      brone('13@brone.ub.ac.id', keepOpen: true),
      Task(
        id: 'm:1',
        source: 'manual',
        uid: '11@brone.ub.ac.id',
        title: 'manual',
        dueAt: hour,
      ),
    ];
    expect(pendingEventIds(tasks), [11, 12]);
    expect(applySubmitted(tasks, {11, 13}), 1);
    expect(tasks[0].done, isTrue);
    expect(tasks[1].done, isFalse);
    expect(tasks[2].done, isFalse);
    expect(tasks[3].done, isFalse);
    expect(eventIdOf('bukan-angka@brone'), isNull);
  });

  testWidgets('PixelButton menjalankan aksi dan efeknya selesai bersih', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PixelButton(
              label: 'Simpan',
              sfx: 'OK!',
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Simpan'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, 1);
    expect(find.byType(PixelBurst), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(PixelBurst), findsNothing);
  });
}
