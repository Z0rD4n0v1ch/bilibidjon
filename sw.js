// Service worker: офлайн-кэш и фоновые обновления.
// VERSION меняет release.sh — после этого телефоны сами скачают новую версию.
const VERSION = "1.3.1";
const CACHE = "bili-" + VERSION;
const CORE = ["./", "./index.html", "./manifest.webmanifest", "./icon.svg", "./icon-192.png", "./icon-512.png"];
const OPTIONAL = [
  "russo-one-cyrillic-400-normal", "russo-one-latin-400-normal",
  "rubik-cyrillic-400-normal", "rubik-cyrillic-500-normal", "rubik-cyrillic-700-normal",
  "rubik-latin-400-normal", "rubik-latin-500-normal", "rubik-latin-700-normal",
].map(f => "./fonts/" + f + ".woff2");

// Скачивание новой версии в фоне. Игроку ничего не мешает: новая версия
// ждёт в статусе "waiting", пока он не нажмёт «Установить».
self.addEventListener("install", e => {
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await c.addAll(CORE.map(u => new Request(u, { cache: "reload" })));
    await Promise.all(OPTIONAL.map(u => c.add(new Request(u, { cache: "reload" })).catch(() => {})));
  })());
});

self.addEventListener("activate", e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k.startsWith("bili-") && k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener("message", e => {
  if (e.data && e.data.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET") return;
  // version.json всегда свежий — по нему игра показывает «что нового»
  if (url.pathname.endsWith("/version.json")) {
    e.respondWith(fetch(e.request, { cache: "no-store" }).catch(() => caches.match(e.request)));
    return;
  }
  if (url.origin === location.origin) {
    e.respondWith(caches.match(e.request, { ignoreSearch: true }).then(r => r || fetch(e.request)));
  } else {
    // шрифты Google: из сети, при офлайне — из кэша
    e.respondWith(caches.open(CACHE).then(async c => {
      try { const r = await fetch(e.request); if (r.ok) c.put(e.request, r.clone()); return r; }
      catch { return (await c.match(e.request)) || Response.error(); }
    }));
  }
});
