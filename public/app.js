const $ = (id) => document.getElementById(id);
const HOUR = 3600000;
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
let data = null;
let filter = 'active';
let needsSetup = false;
let pushSub = null;

// ---------- API ----------
async function api(path, method = 'GET', body) {
  const res = await fetch(`/api${path}`, {
    method,
    credentials: 'same-origin',
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (res.status === 401 && path !== '/login') { showAuth(); }
  if (!res.ok) throw new Error(json.error || 'Terjadi kesalahan.');
  return json;
}

// ---------- Efek tombol ----------
function squash(el) {
  if (reduced.matches) return;
  el.animate([
    { scale: '1 1' }, { scale: '1.16 .8' }, { scale: '.92 1.12' }, { scale: '1.04 .97' }, { scale: '1 1' },
  ], { duration: 320, easing: 'steps(12, end)' });
}

function burst(x, y, word) {
  if (reduced.matches) return;
  const colors = ['#ffd166', '#ef476f', '#7c6ee6', '#2ec482', '#1d1a4a'];
  for (let i = 0; i < 14; i++) {
    const spark = document.createElement('i');
    spark.className = 'spark';
    spark.style.left = `${x}px`;
    spark.style.top = `${y}px`;
    spark.style.background = colors[i % colors.length];
    $('fx').append(spark);
    const angle = (i / 14) * Math.PI * 2;
    const dist = 42 + (i % 3) * 20;
    spark.animate([
      { transform: 'translate(-50%,-50%) scale(1)', opacity: 1 },
      { transform: `translate(${Math.cos(angle) * dist}px,${Math.sin(angle) * dist}px) scale(.4)`, opacity: 0 },
    ], { duration: 460, easing: 'steps(7, end)' }).onfinish = () => spark.remove();
  }
  if (!word) return;
  const sfx = document.createElement('b');
  sfx.className = 'sfx';
  sfx.textContent = word;
  sfx.style.left = `${Math.min(Math.max(x, 60), innerWidth - 60)}px`;
  sfx.style.top = `${Math.max(y - 22, 34)}px`;
  $('fx').append(sfx);
  sfx.animate([
    { transform: 'translate(-50%,-50%) rotate(-8deg) scale(.3)', opacity: 1 },
    { transform: 'translate(-50%,-90%) rotate(-5deg) scale(1.25)', opacity: 1, offset: .3 },
    { transform: 'translate(-50%,-105%) rotate(-5deg) scale(1)', opacity: 1, offset: .75 },
    { transform: 'translate(-50%,-135%) rotate(-5deg) scale(1)', opacity: 0 },
  ], { duration: 680, easing: 'steps(12, end)' }).onfinish = () => sfx.remove();
}

document.addEventListener('click', (e) => {
  const btn = e.target.closest('.px-btn, .check');
  if (!btn) return;
  squash(btn);
  const r = btn.getBoundingClientRect();
  if (btn.dataset.sfx) burst(r.left + r.width / 2, r.top + r.height / 2, btn.dataset.sfx);
});

let toastTimer;
function toast(message) {
  $('toast').textContent = message;
  $('toast').hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { $('toast').hidden = true; }, 3200);
}
function showError(el, message) { el.textContent = message; el.hidden = !message; }

async function busy(btn, fn) {
  btn.disabled = true;
  try { return await fn(); } finally { btn.disabled = false; }
}

// ---------- Render ----------
function dueInfo(task) {
  const left = task.dueAt - Date.now();
  if (task.done) return { text: 'Selesai', cls: '' };
  if (left <= 0) return { text: 'Lewat tenggat', cls: 'late' };
  const hours = Math.floor(left / HOUR);
  const minutes = Math.ceil(left / 60000);
  if (left < HOUR) return { text: `${minutes} menit lagi`, cls: 'urgent' };
  if (hours < 24) return { text: `${hours} jam lagi`, cls: 'urgent' };
  const days = Math.floor(hours / 24);
  return { text: `${days} hari lagi`, cls: days < 3 ? 'soon' : '' };
}

const fmtDate = new Intl.DateTimeFormat('id-ID', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Jakarta' });
const fmtTime = new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Jakarta' });

function el(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

function taskRow(task) {
  const info = dueInfo(task);
  const li = el('li', `task panel${task.done ? ' done' : ''}${info.cls === 'late' ? ' overdue' : ''}`);

  const check = el('button', 'check', task.done ? '✓' : '');
  check.setAttribute('role', 'checkbox');
  check.setAttribute('aria-checked', String(task.done));
  check.setAttribute('aria-label', `Tandai ${task.title} ${task.done ? 'belum selesai' : 'selesai'}`);
  check.addEventListener('click', async () => {
    const r = check.getBoundingClientRect();
    if (!task.done) burst(r.left + 16, r.top + 16, 'CLEAR!');
    try { data = await api(`/tasks/${task.id}`, 'PATCH', { done: !task.done }); render(); }
    catch (err) { toast(err.message); }
  });

  const body = el('div', 'task-body');
  body.append(el('div', 'task-title', task.title));
  const meta = el('div', 'meta');
  meta.append(el('span', `badge ${info.cls}`, info.text));
  meta.append(el('span', '', `${fmtDate.format(task.dueAt)} WIB`));
  if (task.source === 'brone') meta.append(el('span', 'badge src', task.course || 'BRONE'));
  body.append(meta);
  if (task.source === 'brone') {
    const link = el('a', 'link-btn', 'Buka di BRONE ↗');
    link.href = `https://brone.ub.ac.id/calendar/view.php?view=day&time=${Math.floor(task.dueAt / 1000)}`;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    body.append(link);
  }
  li.append(check, body);

  if (task.source === 'manual') {
    const del = el('button', 'del', '✕');
    del.setAttribute('aria-label', `Hapus ${task.title}`);
    del.addEventListener('click', async () => {
      if (!confirm(`Hapus "${task.title}"?`)) return;
      try { data = await api(`/tasks/${task.id}`, 'DELETE'); render(); }
      catch (err) { toast(err.message); }
    });
    li.append(del);
  }
  return li;
}

function render() {
  if (!data) return;
  const now = Date.now();
  const doneCount = data.tasks.filter((t) => t.done).length;
  const urgent = data.tasks.filter((t) => !t.done && t.dueAt > now && t.dueAt - now < 24 * HOUR).length;
  $('xpLabel').textContent = `${doneCount} / ${data.tasks.length} selesai`;
  $('urgentLabel').textContent = urgent ? `${urgent} tugas < 24 jam` : '';
  $('xpFill').style.width = `${data.tasks.length ? (doneCount / data.tasks.length) * 100 : 0}%`;

  if (data.lastError) $('syncLine').textContent = 'Sinkron BRONE bermasalah';
  else if (data.lastSync) $('syncLine').textContent = `Sinkron ${fmtTime.format(data.lastSync)} WIB`;
  else $('syncLine').textContent = 'BRONE belum terhubung';

  const shown = data.tasks
    .filter((t) => t.done === (filter === 'done'))
    .sort((a, b) => (filter === 'done' ? b.dueAt - a.dueAt : a.dueAt - b.dueAt));
  $('taskList').replaceChildren(...shown.map(taskRow));
  $('empty').hidden = shown.length > 0;
  $('empty').textContent = filter === 'done' ? 'Belum ada quest yang selesai.' : 'Tidak ada tugas aktif. Aman!';

  const banner = !data.connected ? 'Hubungkan BRONE supaya tugas masuk otomatis →'
    : data.lastError ? `${data.lastError} Ketuk untuk memperbaiki →`
    : !pushSub ? 'Aktifkan notifikasi supaya tidak ketinggalan tugas →' : '';
  $('setupBanner').textContent = banner;
  $('setupBanner').hidden = !banner;

  $('broneSetup').hidden = data.connected && !data.lastError;
  $('broneActions').hidden = !data.connected;
  $('broneStatus').textContent = !data.connected ? 'Belum terhubung. Password UB tidak disimpan di aplikasi ini.'
    : data.lastError ? data.lastError
    : `Terhubung. Sinkron otomatis tiap 15 menit.`;
  renderPush();
}

// ---------- Push ----------
const pushSupported = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent);
const isStandalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

function renderPush() {
  const toggle = $('pushToggle');
  $('pushTest').hidden = !pushSub;
  toggle.textContent = pushSub ? 'Matikan' : 'Aktifkan';
  toggle.hidden = false;
  if (!window.isSecureContext) {
    $('pushStatus').textContent = 'Notifikasi butuh alamat HTTPS.';
    toggle.hidden = true;
  } else if (isIos && !isStandalone) {
    $('pushStatus').textContent = 'Di iPhone: tekan Share, pilih Add to Home Screen, lalu buka dari ikon itu.';
    toggle.hidden = true;
  } else if (!pushSupported) {
    $('pushStatus').textContent = 'Browser ini belum mendukung push notification.';
    toggle.hidden = true;
  } else if (Notification.permission === 'denied') {
    $('pushStatus').textContent = 'Notifikasi diblokir. Izinkan lewat pengaturan situs di browser.';
    toggle.hidden = true;
  } else {
    $('pushStatus').textContent = pushSub ? 'Aktif di perangkat ini.' : 'Belum aktif di perangkat ini.';
  }
}

function keyBytes(base64) {
  const raw = atob(base64.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(base64.length / 4) * 4, '='));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

async function initPush() {
  if (!pushSupported || !window.isSecureContext) return;
  const reg = await navigator.serviceWorker.register('/sw.js');
  pushSub = await reg.pushManager.getSubscription();
  if (pushSub) await api('/push/subscribe', 'POST', pushSub.toJSON()).catch(() => {});
  render();
}

$('pushToggle').addEventListener('click', (e) => busy(e.currentTarget, async () => {
  try {
    const reg = await navigator.serviceWorker.ready;
    if (pushSub) {
      await api('/push/unsubscribe', 'POST', { endpoint: pushSub.endpoint });
      await pushSub.unsubscribe();
      pushSub = null;
      toast('Notifikasi dimatikan.');
    } else {
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') { render(); return toast('Izin notifikasi belum diberikan.'); }
      pushSub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(data.vapidPublicKey) });
      await api('/push/subscribe', 'POST', pushSub.toJSON());
      toast('Notifikasi aktif!');
    }
    render();
  } catch (err) { toast(err.message); }
}));

$('pushTest').addEventListener('click', (e) => busy(e.currentTarget, async () => {
  try { await api('/push/test', 'POST', {}); toast('Notif tes dikirim.'); }
  catch (err) { toast(err.message); }
}));

// ---------- Auth ----------
function showAuth() {
  document.querySelectorAll('dialog[open]').forEach((d) => d.close());
  $('app').hidden = true;
  $('auth').hidden = false;
  $('authHint').textContent = needsSetup ? 'Buat password untuk mengunci aplikasi ini.' : 'Masuk untuk melihat quest kamu.';
  $('authSubmit').textContent = needsSetup ? 'Buat & masuk' : 'Masuk';
  $('authPassword').autocomplete = needsSetup ? 'new-password' : 'current-password';
}

async function showApp() {
  data = await api('/state');
  needsSetup = false;
  $('auth').hidden = true;
  $('app').hidden = false;
  render();
  initPush().catch(() => {});
}

$('authForm').addEventListener('submit', (e) => {
  e.preventDefault();
  busy($('authSubmit'), async () => {
    showError($('authError'), '');
    try {
      await api(needsSetup ? '/setup' : '/login', 'POST', { password: $('authPassword').value });
      $('authPassword').value = '';
      await showApp();
    } catch (err) { showError($('authError'), err.message); }
  });
});

$('logout').addEventListener('click', async () => {
  await api('/logout', 'POST', {}).catch(() => {});
  data = null;
  showAuth();
});

// ---------- Aksi ----------
document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => b.closest('dialog').close()));
document.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', () => {
  filter = tab.dataset.filter;
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t === tab));
  render();
}));
$('openSettings').addEventListener('click', () => $('settingsDialog').showModal());
$('setupBanner').addEventListener('click', () => $('settingsDialog').showModal());
$('openAdd').addEventListener('click', () => {
  showError($('addError'), '');
  $('addForm').reset();
  $('addDialog').showModal();
  $('addTitle').focus();
});

$('addForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    data = await api('/tasks', 'POST', { title: $('addTitle').value, dueAt: new Date($('addDue').value).getTime() });
    $('addDialog').close();
    render();
  } catch (err) { showError($('addError'), err.message); }
});

$('broneForm').addEventListener('submit', (e) => {
  e.preventDefault();
  busy($('broneSubmit'), async () => {
    showError($('broneError'), '');
    try {
      data = await api('/brone', 'POST', { url: $('broneUrl').value });
      $('broneUrl').value = '';
      render();
      toast('BRONE terhubung!');
    } catch (err) { showError($('broneError'), err.message); }
  });
});

$('syncNow').addEventListener('click', (e) => busy(e.currentTarget, async () => {
  try {
    data = await api('/sync', 'POST', {});
    render();
    toast(data.lastError || 'Sinkron selesai.');
  } catch (err) { toast(err.message); }
}));

$('broneOff').addEventListener('click', async () => {
  if (!confirm('Putuskan BRONE? Tugas yang sudah masuk tetap tersimpan.')) return;
  try { data = await api('/brone', 'DELETE'); render(); }
  catch (err) { toast(err.message); }
});

setInterval(render, 60000);
document.addEventListener('visibilitychange', async () => {
  if (document.hidden || !data) return;
  try { data = await api('/state'); render(); } catch { /* tetap tampilkan data terakhir */ }
});

// ---------- Mulai ----------
try {
  const status = await api('/status');
  needsSetup = status.needsSetup;
  if (status.authed) await showApp(); else showAuth();
} catch {
  needsSetup = false;
  showAuth();
  showError($('authError'), 'Server tidak bisa dihubungi.');
}
