import express from 'express';
import webpush from 'web-push';
import { createHash, randomBytes, randomUUID, scryptSync, timingSafeEqual } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchCalendar, normalizeBroneUrl } from './ical.js';
import { formatDue, markReminded, mergeFeed, pickReminder, reminderLabel } from './tasks.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DATA_DIR = path.resolve(process.env.DATA_DIR || path.join(ROOT, 'data'));
const DATA_FILE = path.join(DATA_DIR, 'state.json');
const PORT = Number(process.env.PORT || 3000);
const IS_PROD = process.env.NODE_ENV === 'production';
const HOST = process.env.HOST || (IS_PROD ? '0.0.0.0' : '127.0.0.1');
const SYNC_MS = 15 * 60 * 1000;
const SESSION_MS = 90 * 24 * 3600 * 1000;
const COOKIE = 'tq_session';

if (IS_PROD && !process.env.APP_PASSWORD) {
  console.error('APP_PASSWORD wajib diisi saat NODE_ENV=production.');
  process.exit(1);
}

// ---------- Penyimpanan ----------
mkdirSync(DATA_DIR, { recursive: true });
const state = existsSync(DATA_FILE)
  ? JSON.parse(readFileSync(DATA_FILE, 'utf8'))
  : { auth: null, sessions: {}, vapid: null, calendarUrl: null, lastSync: null, lastError: null, tasks: [], subscriptions: [] };

function save() {
  const tmp = `${DATA_FILE}.tmp`;
  writeFileSync(tmp, JSON.stringify(state), { mode: 0o600 });
  renameSync(tmp, DATA_FILE);
}

if (!state.vapid) { state.vapid = webpush.generateVAPIDKeys(); save(); }
const appUrl = process.env.APP_URL || '';
webpush.setVapidDetails(
  appUrl.startsWith('https://') ? appUrl : 'mailto:noreply@example.com',
  state.vapid.publicKey,
  state.vapid.privateKey,
);

// ---------- Auth ----------
function hashPassword(password, salt) {
  return scryptSync(password, salt, 32).toString('hex');
}
function setPassword(password) {
  const salt = randomBytes(16).toString('hex');
  state.auth = { salt, hash: hashPassword(password, salt) };
}
function checkPassword(password) {
  if (!state.auth) return false;
  const a = Buffer.from(hashPassword(password, state.auth.salt), 'hex');
  return timingSafeEqual(a, Buffer.from(state.auth.hash, 'hex'));
}
if (process.env.APP_PASSWORD && !(state.auth && checkPassword(process.env.APP_PASSWORD))) {
  setPassword(process.env.APP_PASSWORD);
  state.sessions = {};
  save();
}

const tokenHash = (t) => createHash('sha256').update(t).digest('hex');
function readSession(req) {
  const raw = req.headers.cookie?.split(';').map((c) => c.trim()).find((c) => c.startsWith(`${COOKIE}=`));
  if (!raw) return null;
  const key = tokenHash(raw.slice(COOKIE.length + 1));
  const expires = state.sessions[key];
  if (!expires || expires < Date.now()) return null;
  return key;
}
function startSession(res) {
  const token = randomBytes(32).toString('hex');
  const now = Date.now();
  for (const [k, exp] of Object.entries(state.sessions)) if (exp < now) delete state.sessions[k];
  state.sessions[tokenHash(token)] = now + SESSION_MS;
  save();
  res.cookie(COOKIE, token, { httpOnly: true, sameSite: 'strict', secure: IS_PROD, maxAge: SESSION_MS, path: '/' });
}
const requireAuth = (req, res, next) =>
  readSession(req) ? next() : res.status(401).json({ error: 'Silakan masuk dulu.' });

let failedLogins = 0;
let lockedUntil = 0;

// ---------- Push ----------
async function sendPush(payload) {
  const body = JSON.stringify(payload);
  const results = await Promise.allSettled(state.subscriptions.map((sub) =>
    webpush.sendNotification(sub, body, { TTL: 86400, urgency: 'high' })));
  let delivered = 0;
  const dead = new Set();
  results.forEach((r, i) => {
    if (r.status === 'fulfilled') delivered++;
    else if ([404, 410].includes(r.reason?.statusCode)) dead.add(state.subscriptions[i].endpoint);
    else console.error('Push gagal:', r.reason?.statusCode || r.reason?.message);
  });
  if (dead.size) {
    state.subscriptions = state.subscriptions.filter((s) => !dead.has(s.endpoint));
    save();
  }
  return delivered;
}

let ticking = false;
async function reminderTick() {
  if (ticking || !state.subscriptions.length) return;
  ticking = true;
  try {
    const now = Date.now();
    const active = state.tasks.filter((t) => !t.done && t.dueAt > now);
    const fresh = active.filter((t) => !t.announced);

    if (fresh.length > 3) {
      const delivered = await sendPush({
        title: `${fresh.length} tugas baru dari BRONE`,
        body: `Terdekat: ${[...fresh].sort((a, b) => a.dueAt - b.dueAt)[0].title}`,
        tag: 'tugas-baru', url: '/',
      });
      if (delivered) fresh.forEach((t) => { t.announced = true; t.dueChanged = false; markReminded(t, now); });
    } else {
      for (const t of fresh) {
        const delivered = await sendPush({
          title: t.dueChanged ? 'Tenggat berubah' : 'Tugas baru',
          body: `${t.title}\n${formatDue(t.dueAt)}`,
          tag: t.id, url: '/',
        });
        if (delivered) { t.announced = true; t.dueChanged = false; markReminded(t, now); }
      }
    }

    for (const t of active.filter((x) => x.announced)) {
      const hours = pickReminder(t, now);
      if (!hours) continue;
      const delivered = await sendPush({
        title: `${reminderLabel(hours)}!`,
        body: `${t.title}\n${formatDue(t.dueAt)}`,
        tag: t.id, url: '/',
      });
      if (delivered) markReminded(t, now);
    }
    save();
  } finally {
    ticking = false;
  }
}

// ---------- Sinkron BRONE ----------
let syncing = null;
function syncBrone() {
  if (!state.calendarUrl) return Promise.resolve();
  syncing ??= (async () => {
    try {
      const events = await fetchCalendar(state.calendarUrl);
      state.tasks = mergeFeed(state.tasks, events, Date.now());
      state.lastSync = Date.now();
      state.lastError = null;
    } catch (err) {
      state.lastError = err.message;
      console.error('Sinkron gagal:', err.message);
    } finally {
      save();
      syncing = null;
    }
    await reminderTick();
  })();
  return syncing;
}

// ---------- HTTP ----------
const app = express();
app.disable('x-powered-by');
if (IS_PROD) app.set('trust proxy', 1);
app.use((req, res, next) => {
  res.set({
    'Content-Security-Policy': "default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
  });
  next();
});
app.use(express.json({ limit: '32kb' }));

const publicTask = ({ id, source, title, course, description, dueAt, done }) =>
  ({ id, source, title, course, description, dueAt, done });
const snapshot = () => ({
  tasks: state.tasks.map(publicTask),
  connected: Boolean(state.calendarUrl),
  lastSync: state.lastSync,
  lastError: state.lastError,
  vapidPublicKey: state.vapid.publicKey,
});

app.get('/api/status', (req, res) => {
  res.json({ needsSetup: !state.auth, authed: Boolean(readSession(req)) });
});

app.post('/api/setup', (req, res) => {
  if (state.auth) return res.status(409).json({ error: 'Password sudah dibuat.' });
  const { password } = req.body ?? {};
  if (typeof password !== 'string' || password.length < 8 || password.length > 128) {
    return res.status(400).json({ error: 'Password minimal 8 karakter.' });
  }
  setPassword(password);
  startSession(res);
  res.json({ ok: true });
});

app.post('/api/login', (req, res) => {
  if (Date.now() < lockedUntil) return res.status(429).json({ error: 'Terlalu banyak percobaan. Tunggu 1 menit.' });
  const { password } = req.body ?? {};
  if (typeof password !== 'string' || password.length > 128 || !checkPassword(password)) {
    if (++failedLogins >= 5) { lockedUntil = Date.now() + 60000; failedLogins = 0; }
    return res.status(401).json({ error: 'Password salah.' });
  }
  failedLogins = 0;
  startSession(res);
  res.json({ ok: true });
});

app.post('/api/logout', requireAuth, (req, res) => {
  delete state.sessions[readSession(req)];
  save();
  res.clearCookie(COOKIE, { path: '/' });
  res.json({ ok: true });
});

app.get('/api/state', requireAuth, (req, res) => res.json(snapshot()));

app.post('/api/brone', requireAuth, async (req, res) => {
  try {
    const url = normalizeBroneUrl(req.body?.url);
    await fetchCalendar(url);
    state.calendarUrl = url;
    save();
    await syncBrone();
    res.json(snapshot());
  } catch (err) {
    res.status(400).json({ error: err.message || 'Gagal menghubungkan BRONE.' });
  }
});

app.delete('/api/brone', requireAuth, (req, res) => {
  state.calendarUrl = null;
  state.lastError = null;
  save();
  res.json(snapshot());
});

app.post('/api/sync', requireAuth, async (req, res) => {
  await syncBrone();
  res.json(snapshot());
});

app.post('/api/tasks', requireAuth, (req, res) => {
  const title = typeof req.body?.title === 'string' ? req.body.title.trim() : '';
  const dueAt = Number(req.body?.dueAt);
  if (!title || title.length > 200) return res.status(400).json({ error: 'Judul wajib diisi (maks 200).' });
  if (!Number.isFinite(dueAt) || dueAt <= Date.now()) return res.status(400).json({ error: 'Tenggat harus di masa depan.' });
  state.tasks.push({
    id: randomUUID(), source: 'manual', title, course: '', description: '', dueAt,
    done: false, announced: true, dueChanged: false, sentReminders: [], createdAt: Date.now(),
  });
  save();
  res.json(snapshot());
});

app.patch('/api/tasks/:id', requireAuth, (req, res) => {
  const task = state.tasks.find((t) => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'Tugas tidak ditemukan.' });
  if (typeof req.body?.done !== 'boolean') return res.status(400).json({ error: 'Data tidak valid.' });
  task.done = req.body.done;
  save();
  res.json(snapshot());
});

app.delete('/api/tasks/:id', requireAuth, (req, res) => {
  const task = state.tasks.find((t) => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'Tugas tidak ditemukan.' });
  if (task.source !== 'manual') return res.status(400).json({ error: 'Tugas BRONE tidak bisa dihapus, tandai selesai saja.' });
  state.tasks = state.tasks.filter((t) => t.id !== task.id);
  save();
  res.json(snapshot());
});

app.post('/api/push/subscribe', requireAuth, (req, res) => {
  const sub = req.body;
  let valid = false;
  try { valid = new URL(sub.endpoint).protocol === 'https:' && sub.keys?.p256dh && sub.keys?.auth; } catch { /* tidak valid */ }
  if (!valid) return res.status(400).json({ error: 'Langganan notifikasi tidak valid.' });
  state.subscriptions = state.subscriptions.filter((s) => s.endpoint !== sub.endpoint);
  state.subscriptions.push({ endpoint: sub.endpoint, keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth } });
  save();
  reminderTick().catch(console.error);
  res.json({ ok: true });
});

app.post('/api/push/unsubscribe', requireAuth, (req, res) => {
  state.subscriptions = state.subscriptions.filter((s) => s.endpoint !== req.body?.endpoint);
  save();
  res.json({ ok: true });
});

app.post('/api/push/test', requireAuth, async (req, res) => {
  const delivered = await sendPush({ title: 'Notif aktif!', body: 'Pengingat tugas akan muncul seperti ini.', tag: 'tes', url: '/' });
  if (!delivered) return res.status(502).json({ error: 'Notifikasi belum terkirim ke perangkat.' });
  res.json({ delivered });
});

app.use('/api', (req, res) => res.status(404).json({ error: 'Tidak ditemukan.' }));
for (const font of ['vt323', 'press-start-2p']) {
  app.use('/fonts', express.static(path.join(ROOT, `node_modules/@fontsource/${font}/files`), { maxAge: '30d' }));
}
app.use(express.static(path.join(ROOT, 'public'), { maxAge: 0 }));

app.listen(PORT, HOST, () => {
  console.log(`Tugas Quest berjalan di http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${PORT}`);
  syncBrone();
  setInterval(syncBrone, SYNC_MS);
  setInterval(() => reminderTick().catch(console.error), 60000);
});
