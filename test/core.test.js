import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeBroneUrl, parseCalendar, parseIcalDate } from '../server/ical.js';
import { markReminded, mergeFeed, pickReminder } from '../server/tasks.js';

const HOUR = 3600000;
const ICS = [
  'BEGIN:VCALENDAR',
  'BEGIN:VEVENT', 'UID:1@brone', 'SUMMARY:Laporan Praktikum\\, Bab 2 is due',
  'DESCRIPTION:Kumpulkan\\nPDF', 'CATEGORIES:PBO-A', 'DTSTART:20261201T100000Z', 'END:VEVENT',
  'BEGIN:VEVENT', 'UID:2@brone', 'SUMMARY:Kuis 1 opens', 'DTSTART:20261201T100000Z', 'END:VEVENT',
  'END:VCALENDAR',
].join('\r\n');

test('parseCalendar mengambil tugas dan membuang acara dibuka', () => {
  const events = parseCalendar(ICS);
  assert.equal(events.length, 1);
  assert.equal(events[0].title, 'Laporan Praktikum, Bab 2 is due');
  assert.equal(events[0].course, 'PBO-A');
  assert.equal(events[0].dueAt, Date.UTC(2026, 11, 1, 10));
});

test('parseCalendar menolak halaman non-kalender', () => {
  assert.throws(() => parseCalendar('<html>login</html>'));
});

test('waktu tanpa zona dibaca sebagai WIB', () => {
  assert.equal(parseIcalDate('20261201T170000'), Date.UTC(2026, 11, 1, 10));
});

test('normalizeBroneUrl hanya menerima link kalender BRONE', () => {
  const ok = normalizeBroneUrl('https://brone.ub.ac.id/calendar/export_execute.php?userid=5&authtoken=abc&preset_what=user&preset_time=weeknow');
  assert.match(ok, /preset_what=all/);
  assert.match(ok, /preset_time=recentupcoming/);
  for (const bad of [
    'http://brone.ub.ac.id/calendar/export_execute.php?userid=5&authtoken=abc',
    'https://brone.ub.ac.id.evil.test/calendar/export_execute.php?userid=5&authtoken=abc',
    'https://user@brone.ub.ac.id/calendar/export_execute.php?userid=5&authtoken=abc',
    'https://brone.ub.ac.id/login/index.php?userid=5&authtoken=abc',
    'https://brone.ub.ac.id/calendar/export_execute.php?userid=5',
  ]) assert.throws(() => normalizeBroneUrl(bad), undefined, bad);
});

test('mergeFeed menambah, memperbarui tenggat, dan menghapus tugas yang hilang', () => {
  const now = 1000;
  let tasks = mergeFeed([], [{ uid: 'a', title: 'A', dueAt: now + HOUR }, { uid: 'b', title: 'B', dueAt: now + HOUR }, { uid: 'old', title: 'Lama', dueAt: now - 1 }], now);
  assert.equal(tasks.length, 2);
  tasks[0].announced = true;
  tasks[0].sentReminders = [1];
  tasks = mergeFeed(tasks, [{ uid: 'a', title: 'A', dueAt: now + 2 * HOUR }], now);
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].announced, false);
  assert.equal(tasks[0].dueChanged, true);
  assert.deepEqual(tasks[0].sentReminders, []);
});

test('pengingat terkirim sekali per ambang dan tidak untuk tugas selesai', () => {
  const now = 0;
  const task = { dueAt: 5 * HOUR, done: false, sentReminders: [] };
  assert.equal(pickReminder(task, now), 6);
  markReminded(task, now);
  assert.equal(pickReminder(task, now), null);
  assert.equal(pickReminder(task, 4.5 * HOUR), 1);
  assert.equal(pickReminder({ ...task, done: true }, 4.5 * HOUR), null);
  assert.equal(pickReminder({ dueAt: 100 * HOUR, done: false, sentReminders: [] }, now), null);
});
