// Musika — Service Worker
// Cache-first strategy for static shell assets, network-only for API calls.
// Bump CACHE_VERSION to force clients to re-download updated HTML/assets.

const CACHE_VERSION = 'musika-v4';
const STATIC_ASSETS = [
  './',
  './host.html',
  './timeline-admin.html',
  './tokens-print.html',
  './print.html',
  './manifest.json',
  './icon.svg',
  './icon-180.png',
  './icon-192.png',
  './icon-512.png',
];

// External CDN scripts — cache them too so first launch is the only slow one
const CDN_ASSETS = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js',
  'https://cdn.jsdelivr.net/npm/html5-qrcode@2.3.8/html5-qrcode.min.js',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then(cache => {
      // Cache in two passes so a single 404 on a CDN doesn't kill the install
      return cache.addAll(STATIC_ASSETS).then(() =>
        Promise.allSettled(CDN_ASSETS.map(url =>
          cache.add(new Request(url, { mode: 'no-cors' })).catch(() => {})
        ))
      );
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_VERSION).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Never intercept non-GET (writes, auth, etc.)
  if (request.method !== 'GET') return;

  // NEVER cache: Supabase API, Spotify API, anything with "/rest/", "/auth/", "/functions/"
  const isApi =
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('api.spotify.com') ||
    url.hostname.includes('accounts.spotify.com') ||
    url.pathname.includes('/rest/') ||
    url.pathname.includes('/functions/') ||
    url.pathname.includes('/auth/');
  if (isApi) return; // fall through to network

  // Spotify SDK + embed script: bypass cache (they update frequently)
  if (url.hostname === 'sdk.scdn.co' || url.hostname === 'open.spotify.com') return;

  // Cache-first for everything else (shell + CDN libs)
  event.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(response => {
        // Only cache successful, basic/cors responses
        if (response && response.status === 200 && (response.type === 'basic' || response.type === 'cors')) {
          const clone = response.clone();
          caches.open(CACHE_VERSION).then(c => c.put(request, clone)).catch(() => {});
        }
        return response;
      }).catch(() => {
        // Offline fallback for navigation requests: serve host.html
        if (request.mode === 'navigate') {
          return caches.match('./host.html');
        }
      });
    })
  );
});
