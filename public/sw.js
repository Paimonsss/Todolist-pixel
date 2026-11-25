const CACHE = 'tugas-quest-v2';
const SHELL = ['/', '/style.css', '/app.js', '/manifest.webmanifest', '/icons/icon-192.png',
  '/fonts/vt323-latin-400-normal.woff2', '/fonts/press-start-2p-latin-400-normal.woff2'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return;
  event.respondWith(fetch(event.request).then((res) => {
    if (res.ok) {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(event.request, copy));
    }
    return res;
  }).catch(() => caches.match(event.request).then((hit) => hit || caches.match('/'))));
});

self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data.json(); } catch { data = { title: 'Tugas Quest', body: event.data?.text() }; }
  event.waitUntil(self.registration.showNotification(data.title || 'Tugas Quest', {
    body: data.body || '',
    tag: data.tag,
    renotify: Boolean(data.tag),
    requireInteraction: true,
    icon: '/icons/icon-192.png',
    badge: '/icons/icon-96.png',
    vibrate: [120, 60, 120, 60, 240],
    data: { url: '/' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    const open = list.find((c) => new URL(c.url).origin === location.origin);
    return open ? open.focus() : self.clients.openWindow('/');
  }));
});
