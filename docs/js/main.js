// main.js — «режиссёр» приложения, как Main в Godot-версии.
//
// Экраны ничего не знают друг о друге: они сообщают, что случилось
// (onStart, onOpenStack), а main решает, что показать дальше.

import { updateScale, openLayer, popupStack } from "./ui.js";
import { AppData } from "./data.js";
import { createStartScreen } from "./screens/start.js";
import { createStacksScreen } from "./screens/stacks.js";
import { openStackScreen } from "./screens/stack.js";

updateScale();
window.addEventListener("resize", updateScale);

let currentScreen = null;

/** Плавная смена экрана: новый проявляется, старый растворяется. */
function switchTo(build) {
	const old = currentScreen;
	const layer = openLayer({ className: "screen" });
	build(layer);
	requestAnimationFrame(() => requestAnimationFrame(() => layer.root.classList.add("shown")));
	if (old) {
		old.root.classList.remove("shown");
		old.root.style.pointerEvents = "none";
		setTimeout(() => old.root.remove(), 350);
	}
	currentScreen = layer;
}

function showStart() {
	switchTo((layer) => layer.frame.append(...createStartScreen({ onStart: showStacks })));
}

function showStacks() {
	switchTo((layer) => createStacksScreen(layer, { onOpenStack: openStackScreen }));
}

// Esc на ПК закрывает самый верхний попап (как «Назад» на Android).
document.addEventListener("keydown", (e) => {
	if (e.key === "Escape") popupStack.at(-1)?.onCancel?.();
});

await AppData.init();
showStart();

// ---------------------------------------------------------------------------
// Работа без интернета: service worker хранит копию файлов приложения.
// Когда выходит новая версия, он сам обновляется, а страница перезагружается.
// ---------------------------------------------------------------------------
if ("serviceWorker" in navigator) {
	const hadController = Boolean(navigator.serviceWorker.controller);
	navigator.serviceWorker.register("index.service.worker.js");
	let reloaded = false;
	navigator.serviceWorker.addEventListener("controllerchange", () => {
		if (hadController && !reloaded) { reloaded = true; AppData.saveNow().then(() => location.reload()); }
	});
}
