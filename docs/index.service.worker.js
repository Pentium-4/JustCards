// Service worker: хранит копию приложения, чтобы оно открывалось без интернета.
//
// Файл называется так же, как у прошлой Godot-версии. Благодаря этому айфон,
// на котором стоит старая версия, при следующем запуске сам заменит её на эту.
//
// Стратегия «сначала сеть»: если интернет есть — берём свежие файлы
// (и обновляем копию), если нет — открываем сохранённую копию.

const CACHE_NAME = "just-cards-web-1.2";
const FILES = [
	"./",
	"index.html",
	"style.css",
	"manifest.json",
	"js/main.js", "js/ui.js", "js/data.js", "js/platform.js", "js/gesture.js", "js/popups.js", "js/version.js",
	"js/screens/start.js", "js/screens/stacks.js", "js/screens/stack.js",
	"fonts/abel.woff2", "fonts/roboto-condensed-cyrillic.woff2", "fonts/noto-sans-georgian.woff2",
	"img/bg_main.png", "img/icon_180.png", "img/icon.svg",
	...["add_image", "arrow_left", "arrow_right", "check", "close", "load", "loop", "rotate", "save", "shuffle", "trash"]
		.map((n) => `icons/icon_${n}.svg`),
];

self.addEventListener("install", (event) => {
	self.skipWaiting();
	event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(FILES)));
});

self.addEventListener("activate", (event) => {
	// Удаляем все старые копии, в том числе от Godot-версии (40 МБ).
	event.waitUntil((async () => {
		for (const key of await caches.keys()) if (key !== CACHE_NAME) await caches.delete(key);
		await self.clients.claim();
	})());
});

self.addEventListener("fetch", (event) => {
	if (event.request.method !== "GET") return;
	event.respondWith((async () => {
		const cache = await caches.open(CACHE_NAME);
		try {
			const response = await fetch(event.request);
			if (response.ok && new URL(event.request.url).origin === location.origin) {
				cache.put(event.request, response.clone());
			}
			return response;
		} catch {
			return (await cache.match(event.request, { ignoreSearch: true })) ?? Response.error();
		}
	})());
});
