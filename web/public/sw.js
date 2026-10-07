/* Service Worker: Offline-Shell + Web-Push-Benachrichtigungen */
const CACHE = 'tonne-torte-v1';
const SHELL = ['./', './index.php', './manifest.webmanifest', './assets/app.css', './assets/app.js',
  './assets/icons/icon-192.png', './assets/icons/icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL).catch(() => null)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  // API, Feed und Cron immer live
  if (/\/(api|feed|cron)\.php/.test(url.pathname)) return;

  if (url.pathname.endsWith('/assets/app.js') || url.pathname.endsWith('/assets/app.css')
      || url.pathname.includes('/assets/icons/') || url.pathname.endsWith('manifest.webmanifest')) {
    // Assets: Cache zuerst, im Hintergrund aktualisieren
    event.respondWith(
      caches.match(event.request).then((cached) => {
        const network = fetch(event.request).then((res) => {
          if (res.ok) caches.open(CACHE).then((c) => c.put(event.request, res.clone()));
          return res;
        }).catch(() => cached);
        return cached || network;
      })
    );
    return;
  }
  // Seite: Netz zuerst, sonst Cache
  event.respondWith(
    fetch(event.request).then((res) => {
      if (res.ok) caches.open(CACHE).then((c) => c.put(event.request, res.clone()));
      return res;
    }).catch(() => caches.match(event.request).then((c) => c || caches.match('./')))
  );
});

self.addEventListener('push', (event) => {
  let data = { title: 'Tonne & Torte', body: 'Erinnerung', tag: 'tonne', url: './' };
  try {
    data = Object.assign(data, event.data ? event.data.json() : {});
  } catch (e) {
    if (event.data) data.body = event.data.text();
  }
  event.waitUntil(self.registration.showNotification(data.title, {
    body: data.body,
    tag: data.tag || 'tonne',
    icon: './assets/icons/icon-192.png',
    badge: './assets/icons/badge-96.png',
    data: { url: data.url || './' },
    renotify: true,
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      return self.clients.openWindow(target);
    })
  );
});
