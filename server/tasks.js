import { randomUUID } from 'node:crypto';

/** Jam sebelum tenggat saat pengingat dikirim. */
export const REMINDER_HOURS = [72, 24, 6, 1];
const HOUR = 3600 * 1000;

export function mergeFeed(tasks, events, now) {
  const existing = new Map(tasks.filter((t) => t.source === 'brone').map((t) => [t.uid, t]));
  const seen = new Set();
  const added = [];

  for (const event of events) {
    seen.add(event.uid);
    const task = existing.get(event.uid);
    if (task) {
      task.title = event.title;
      task.course = event.course || '';
      task.description = event.description || '';
      if (task.dueAt !== event.dueAt) {
        task.dueAt = event.dueAt;
        task.sentReminders = [];
        if (!task.done) { task.announced = false; task.dueChanged = true; }
      }
    } else if (event.dueAt > now) {
      added.push({
        id: randomUUID(),
        source: 'brone',
        uid: event.uid,
        title: event.title,
        course: event.course || '',
        description: event.description || '',
        dueAt: event.dueAt,
        done: false,
        announced: false,
        dueChanged: false,
        sentReminders: [],
        createdAt: now,
      });
    }
  }

  // Tugas mendatang yang hilang dari BRONE berarti dihapus dosen.
  const kept = tasks.filter((t) =>
    t.source !== 'brone' || seen.has(t.uid) || t.done || t.dueAt <= now);
  return [...kept, ...added];
}

export function pickReminder(task, now) {
  if (task.done || task.dueAt <= now) return null;
  const remaining = task.dueAt - now;
  const hit = [...REMINDER_HOURS].reverse().find((h) => remaining <= h * HOUR);
  if (!hit || task.sentReminders.includes(hit)) return null;
  return hit;
}

/** Menandai ambang ini dan ambang yang lebih panjang agar tidak terkirim dobel. */
export function markReminded(task, now) {
  const remaining = task.dueAt - now;
  const passed = REMINDER_HOURS.filter((h) => remaining <= h * HOUR);
  task.sentReminders = [...new Set([...task.sentReminders, ...passed])];
}

export function formatDue(ms) {
  return new Intl.DateTimeFormat('id-ID', {
    weekday: 'short', day: 'numeric', month: 'short',
    hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Jakarta',
  }).format(ms) + ' WIB';
}

export function reminderLabel(hours) {
  if (hours === 1) return 'Sisa 1 jam';
  if (hours === 6) return 'Sisa 6 jam';
  if (hours === 24) return 'Besok tenggat';
  return 'Sisa 3 hari';
}
