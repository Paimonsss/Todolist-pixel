const WIB_OFFSET_MS = 7 * 3600 * 1000;

function unescapeText(value) {
  return value
    .replace(/\\n/gi, '\n')
    .replace(/\\([,;\\])/g, '$1')
    .trim();
}

/** Mengubah nilai DTSTART iCal ke epoch ms. Waktu tanpa zona dianggap WIB. */
export function parseIcalDate(value) {
  const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(value.trim());
  if (!m) return null;
  const [, y, mo, d, h, mi, s, utc] = m;
  if (h === undefined) {
    // Acara sehari penuh: tenggatnya akhir hari itu (WIB).
    return Date.UTC(+y, +mo - 1, +d, 23, 59, 0) - WIB_OFFSET_MS;
  }
  const asUtc = Date.UTC(+y, +mo - 1, +d, +h, +mi, +s);
  return utc ? asUtc : asUtc - WIB_OFFSET_MS;
}

/** Acara "dibuka" bukan tugas yang perlu dikejar, jadi tidak dimasukkan. */
export function isOpeningEvent(summary) {
  return /(\bopens|\bis open|\bdibuka|\bmulai)\s*\)?\s*$/i.test(summary);
}

export function parseCalendar(text) {
  if (!/BEGIN:VCALENDAR/.test(text)) {
    throw new Error('Respons BRONE bukan kalender. Link mungkin sudah tidak berlaku.');
  }
  const lines = text.replace(/\r\n/g, '\n').replace(/\n[ \t]/g, '').split('\n');
  const events = [];
  let current = null;

  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') { current = {}; continue; }
    if (line === 'END:VEVENT') {
      if (current?.uid && current.title && current.dueAt && !isOpeningEvent(current.title)) {
        events.push(current);
      }
      current = null;
      continue;
    }
    if (!current) continue;
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const key = line.slice(0, colon).split(';')[0].toUpperCase();
    const value = line.slice(colon + 1);
    if (key === 'UID') current.uid = value.trim();
    else if (key === 'SUMMARY') current.title = unescapeText(value);
    else if (key === 'DESCRIPTION') current.description = unescapeText(value).slice(0, 2000);
    else if (key === 'CATEGORIES') current.course = unescapeText(value);
    else if (key === 'DTSTART') current.dueAt = parseIcalDate(value);
  }
  return events;
}

/** Hanya menerima link ekspor kalender BRONE, lalu memaksa rentang semua acara mendatang. */
export function normalizeBroneUrl(input) {
  let url;
  try { url = new URL(String(input).trim()); } catch { throw new Error('Link tidak valid.'); }
  if (url.protocol !== 'https:' || url.hostname !== 'brone.ub.ac.id' || url.port !== '' ||
      url.username || url.password || url.pathname !== '/calendar/export_execute.php') {
    throw new Error('Gunakan link dari halaman Export calendar di brone.ub.ac.id.');
  }
  if (!url.searchParams.get('userid') || !url.searchParams.get('authtoken')) {
    throw new Error('Link belum lengkap. Salin seluruh link kalendernya.');
  }
  url.searchParams.set('preset_what', 'all');
  url.searchParams.set('preset_time', 'recentupcoming');
  return url.toString();
}

export async function fetchCalendar(calendarUrl) {
  const url = normalizeBroneUrl(calendarUrl);
  let lastError;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await fetch(url, {
        redirect: 'manual',
        signal: AbortSignal.timeout(20000),
        headers: { accept: 'text/calendar,text/plain;q=0.9' },
      });
      if (res.status >= 300 && res.status < 400) {
        throw new Error('BRONE meminta login. Buat ulang link kalender.');
      }
      if (!res.ok) throw new Error(`BRONE membalas status ${res.status}.`);
      const text = await res.text();
      if (text.length > 5_000_000) throw new Error('Kalender terlalu besar.');
      return parseCalendar(text);
    } catch (err) {
      lastError = err;
      if (/login|bukan kalender|terlalu besar/.test(err.message)) break;
    }
  }
  throw lastError;
}
