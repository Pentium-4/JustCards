// ui.js — маленькие строительные блоки интерфейса.
//
// Здесь нет логики приложения, только «кирпичики»:
//   h()        — создать HTML-элемент (как добавить узел в сцену Godot);
//   button()   — кнопка с иконкой или текстом (аналог IconButton);
//   openLayer()— новый слой поверх остальных: экран или попап;
//   масштаб    — пересчёт размеров под экран телефона.

export const DESIGN_W = 1125;
export const DESIGN_H = 2436;

// ---------------------------------------------------------------------------
// Масштаб. Макет 1125×2436 вписывается в экран целиком; если экран другой
// формы, «сцена» становится шире или выше, а макет стоит по центру.
// ---------------------------------------------------------------------------

export let scale = 1;

export function updateScale() {
	const w = window.innerWidth;
	const h = window.innerHeight;
	scale = Math.min(w / DESIGN_W, h / DESIGN_H);
	const sw = w / scale;
	const sh = h / scale;
	const root = document.documentElement.style;
	root.setProperty("--s", scale);
	root.setProperty("--sw", sw + "px");
	root.setProperty("--sh", sh + "px");
	root.setProperty("--fx", (sw - DESIGN_W) / 2 + "px");
	root.setProperty("--fy", (sh - DESIGN_H) / 2 + "px");
}

/** Переводит точку экрана (clientX/Y) в координаты сцены (пиксели макета). */
export function toStage(x, y) {
	return { x: x / scale, y: y / scale };
}

// ---------------------------------------------------------------------------
// Создание элементов
// ---------------------------------------------------------------------------

/**
 * h("div", {class: "panel", style: {left: "10px"}}, ...дети)
 * Короткий способ создать элемент с классами, стилями и детьми.
 */
export function h(tag, props = {}, ...children) {
	const el = document.createElement(tag);
	for (const [key, value] of Object.entries(props)) {
		if (key === "style") Object.assign(el.style, value);
		else if (key === "class") el.className = value;
		else if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
		else el.setAttribute(key, value);
	}
	for (const child of children.flat()) {
		if (child != null) el.append(child);
	}
	return el;
}

/** Ставит элемент в координаты макета: left, top, width, height. */
export function place(el, x, y, w, h) {
	Object.assign(el.style, { left: x + "px", top: y + "px", width: w + "px", height: h + "px" });
	return el;
}

export function icon(name, sizePx, { color = "#fff", rotate = 0 } = {}) {
	const i = h("div", { class: "icon" });
	i.style.setProperty("--icon", `url("icons/icon_${name}.svg")`);
	i.style.setProperty("--isz", sizePx + "px");
	i.style.setProperty("--ic", color);
	if (rotate) i.style.setProperty("--rot", rotate + "deg");
	return h("div", { class: "icon-wrap" }, i);
}

/**
 * Кнопка как IconButton в Godot.
 * button({x, y, w, h, color, icon, iconScale, iconColor, rotate, radius, caption, fontSize, flat, onClick})
 * radius не указан → круг.
 */
export function button(o) {
	const b = h("button", { class: "btn" + (o.flat ? " flat" : ""), type: "button" });
	place(b, o.x, o.y, o.w, o.h ?? o.w);
	if (o.color) b.style.setProperty("--c", o.color);
	if (o.radius != null) b.style.borderRadius = o.radius + "px";
	if (o.icon) {
		const side = Math.min(o.w, o.h ?? o.w) * (o.iconScale ?? 0.6);
		b.append(icon(o.icon, side, { color: o.iconColor, rotate: o.rotate }));
	}
	if (o.caption) {
		b.append(h("span", { class: "caption", style: { fontSize: (o.fontSize ?? 64) + "px" } }, o.caption));
	}
	if (o.onClick) b.addEventListener("click", (e) => { e.stopPropagation(); o.onClick(e); });
	return b;
}

/** Меняет иконку у существующей кнопки. */
export function setButtonIcon(b, name) {
	const i = b.querySelector(".icon");
	if (i) i.style.setProperty("--icon", `url("icons/icon_${name}.svg")`);
}

/** Покачивание: «так нельзя» или «тащи сюда, а не нажимай». */
export function wiggle(el) {
	el.animate(
		[{ rotate: "0deg" }, { rotate: "-12deg" }, { rotate: "10deg" }, { rotate: "-6deg" }, { rotate: "3deg" }, { rotate: "0deg" }],
		{ duration: 300 },
	);
}

// ---------------------------------------------------------------------------
// Слои: экран или попап. У каждого слоя своя «сцена» с рамкой макета.
// ---------------------------------------------------------------------------

const layers = () => document.getElementById("layers");

/** Все открытые попапы, сверху — последний. Нужно для кнопки «Назад». */
export const popupStack = [];

/**
 * Открывает слой. blur: true — под ним всё размывается (как BlurOverlay).
 * Возвращает { root, stage, frame, close() }.
 */
export function openLayer({ blur = false, className = "" } = {}) {
	const root = h("div", { class: "layer " + className });
	if (blur) root.append(h("div", { class: "blur" }));
	const frame = h("div", { class: "frame" });
	const stage = h("div", { class: "stage" }, frame);
	root.append(stage);
	layers().append(root);
	// Двойной кадр: сначала элемент появляется, потом включается анимация.
	requestAnimationFrame(() => requestAnimationFrame(() => root.classList.add("open")));

	const layer = {
		root, stage, frame,
		closed: false,
		onCancel: null, // что делать по «Назад» / Esc
		close() {
			if (layer.closed) return Promise.resolve();
			layer.closed = true;
			const i = popupStack.indexOf(layer);
			if (i !== -1) popupStack.splice(i, 1);
			root.classList.remove("open");
			root.classList.add("closing");
			return new Promise((resolve) => setTimeout(() => { root.remove(); resolve(); }, 300));
		},
	};
	if (blur) popupStack.push(layer);
	return layer;
}
