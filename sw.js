/*
 * XVVIIX service worker - makes the app genuinely usable offline.
 *
 * Strategy:
 *   app shell  -> cache-first, refreshed in the background (stale-while-revalidate)
 *   engine dl  -> cache-first, so the installer files stay grabbable offline
 *   everything else (blob:, localhost engine, ranges) -> never touched
 */

const VERSION = 'xvviix-v3';
const SHELL = [
  './',
  './index.html',
  './splitter.worker.js',
  './manifest.webmanifest',
  './og.svg',
  './404.html',
  './engine/xvviix_engine.py',
  './engine/install-xvviix.bat',
  './engine/install-xvviix.sh',
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(VERSION);
    // addAll fails the whole install if any single file 404s, so be tolerant.
    await Promise.all(SHELL.map(async url => {
      try { await cache.add(new Request(url, { cache: 'reload' })); }
      catch (e) { /* optional asset, ignore */ }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('message', event => {
  if (event.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const req = event.request;

  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Never intercept the local Demucs engine, blob URLs, or range requests
  // (partial responses cannot be cached and would break audio seeking).
  if (url.origin !== self.location.origin) return;
  if (req.headers.has('range')) return;

  // The app is a single HTML file that changes on every deploy, and the
  // worker script must never be served stale either. For those, always try
  // the network first and only fall back to the cache when offline.
  const isDocument = req.mode === 'navigate' ||
                     url.pathname === '/' ||
                     url.pathname.endsWith('/') ||
                     url.pathname.endsWith('index.html');
  const isCode = url.pathname.endsWith('splitter.worker.js') ||
                 url.pathname.endsWith('sw.js');

  event.respondWith((async () => {
    const cache = await caches.open(VERSION);

    if (isDocument || isCode) {
      try {
        const fresh = await fetch(req, { cache: 'no-store' });
        if (fresh && fresh.status === 200) {
          cache.put(req, fresh.clone()).catch(() => {});
          return fresh;
        }
      } catch (e) { /* offline, fall through */ }

      const cached = await cache.match(req, { ignoreSearch: true }) ||
                     await cache.match('./index.html') ||
                     await cache.match('./');
      return cached || new Response('Offline', { status: 503, statusText: 'Offline' });
    }

    // Static assets (icons, installer files): cache-first is fine and fast.
    const cached = await cache.match(req, { ignoreSearch: true });
    if (cached) {
      fetch(req).then(res => {
        if (res && res.status === 200 && res.type === 'basic') {
          cache.put(req, res.clone()).catch(() => {});
        }
      }).catch(() => {});
      return cached;
    }

    try {
      const fresh = await fetch(req);
      if (fresh && fresh.status === 200 && fresh.type === 'basic') {
        cache.put(req, fresh.clone()).catch(() => {});
      }
      return fresh;
    } catch (e) {
      return new Response('Offline', { status: 503, statusText: 'Offline' });
    }
  })());
});
