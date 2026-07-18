const CACHE_NAME = 'openmail-v2';
const STATIC_ASSETS = [
  '/',
  '/login',
  '/static/app.css',
  '/static/js/app.js',
  '/static/js/ui.js',
  '/static/js/utils.js',
  '/static/manifest.json',
  '/static/icon-192.png',
  '/static/icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS);
    }).catch(() => {
      // Ignore CDN/font failures; we only cache core app shell
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // API requests: network first, fallback to empty JSON if offline
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request)
        .then((res) => res)
        .catch(() => {
          return new Response(
            JSON.stringify({ error: 'offline', items: [] }),
            { status: 503, headers: { 'Content-Type': 'application/json' } }
          );
        })
    );
    return;
  }

  // Static assets: cache first, then network fallback and update cache
  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) {
        // background update
        fetch(request).then((res) => {
          if (res.ok) {
            caches.open(CACHE_NAME).then((cache) => cache.put(request, res));
          }
        }).catch(() => {});
        return cached;
      }
      return fetch(request).then((res) => {
        if (res.ok && request.method === 'GET') {
          const clone = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
        }
        return res;
      });
    })
  );
});
