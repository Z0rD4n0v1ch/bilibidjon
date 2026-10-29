// Service worker: офлайн-кэш и фоновые обновления с прогрессом.
// VERSION меняет release.sh — после этого игра у игроков сама скачает новую версию.
const VERSION = "1.8.1";
const CACHE = "bili-" + VERSION;
const CORE = ["./", "./index.html", "./manifest.webmanifest", "./icon.svg", "./icon-180.png", "./icon-192.png", "./icon-512.png"];
const OPTIONAL = [
  "russo-one-cyrillic-400-normal", "russo-one-latin-400-normal",
  "rubik-cyrillic-400-normal", "rubik-cyrillic-500-normal", "rubik-cyrillic-700-normal",
  "rubik-latin-400-normal", "rubik-latin-500-normal", "rubik-latin-700-normal",
].map(f => "./fonts/" + f + ".woff2");

async function tell(msg) {
  const list = await self.clients.matchAll({ includeUncontrolled: true, type: "window" });
  list.forEach(c => c.postMessage(Object.assign({ version: VERSION }, msg)));
}

// Скачиваем новую версию по файлам и сообщаем игре прогресс (0…1).
self.addEventListener("install", e => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    const files = [...CORE, ...OPTIONAL];
    let done = 0;
    await tell({ type: "SW_PROGRESS", p: 0 });
    for (const url of files) {
      const optional = OPTIONAL.includes(url);
      try {
        const res = await fetch(new Request(url, { cache: "reload" }));
        if (!res.ok) throw new Error(url + " " + res.status);
        const len = +res.headers.get("content-length") || 0, type = res.headers.get("content-type") || "";
        let body;
        if (res.body && len) {
          const reader = res.body.getReader(), chunks = [];
          let got = 0, last = 0;
          for (;;) {
            const { done: end, value } = await reader.read();
            if (end) break;
            chunks.push(value); got += value.length;
            const now = Date.now();
            if (now - last > 150) { last = now; tell({ type: "SW_PROGRESS", p: (done + Math.min(0.99, got / len)) / files.length }); }
          }
          body = new Blob(chunks, { type });
        } else body = await res.blob();
        await cache.put(url, new Response(body, { status: 200, headers: type ? { "Content-Type": type } : {} }));
      } catch (err) {
        if (!optional) { await tell({ type: "SW_ERROR" }); throw err; }
      }
      done++;
      await tell({ type: "SW_PROGRESS", p: done / files.length });
    }
  })());
});

// Установка: переключаемся на новую версию и удаляем старую.
self.addEventListener("activate", e => {
  e.waitUntil((async () => {
    await tell({ type: "SW_STEP", step: 2 });
    for (const k of await caches.keys()) if (k.startsWith("bili-") && k !== CACHE) await caches.delete(k);
    await tell({ type: "SW_STEP", step: 3 });
    await self.clients.claim();
  })());
});

self.addEventListener("message", e => {
  if (e.data && e.data.type === "SKIP_WAITING") self.skipWaiting();
});

// Нажатие на уведомление открывает игру
self.addEventListener("notificationclick", e => {
  e.notification.close();
  e.waitUntil((async () => {
    const list = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    if (list.length) return list[0].focus();
    return self.clients.openWindow("./");
  })());
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET") return;
  if (url.pathname.endsWith("/version.json")) {
    e.respondWith(fetch(e.request, { cache: "no-store" }).catch(() => caches.match(e.request, { ignoreSearch: true })));
    return;
  }
  if (url.origin === location.origin) {
    e.respondWith(caches.match(e.request, { ignoreSearch: true }).then(r => r || fetch(e.request)));
  } else {
    e.respondWith(caches.open(CACHE).then(async c => {
      try { const r = await fetch(e.request); if (r.ok) c.put(e.request, r.clone()); return r; }
      catch { return (await c.match(e.request)) || Response.error(); }
    }));
  }
});
