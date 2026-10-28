// gesture.js — жест «нажал — подержал — потащил» (аналог LongPressGesture в Godot).
//
// Распознаёт:
//   короткое нажатие                  → onTap
//   долгое нажатие и перенос          → onDragStart / onDragMove / onDragEnd
//   палец сдвинулся до срабатывания   → ничего: это прокрутка или свайп
// Координаты передаются в пикселях экрана (clientX / clientY).

import { scale } from "./ui.js";

const LONG_PRESS_MS = 450;
const MOVE_TOLERANCE = 24; // в пикселях макета

// Пока что-то тащим, страница не должна прокручиваться.
let dragging = false;
document.addEventListener("touchmove", (e) => { if (dragging) e.preventDefault(); }, { passive: false });

export function longPress(el, { onTap, onDragStart, onDragMove, onDragEnd }) {
	let state = "none"; // "none" | "pressing" | "dragging"
	let startX = 0, startY = 0, timer = 0, pointerId = 0;

	const reset = () => { state = "none"; dragging = false; clearTimeout(timer); };

	el.addEventListener("pointerdown", (e) => {
		if (e.button !== 0) return;
		state = "pressing";
		startX = e.clientX; startY = e.clientY; pointerId = e.pointerId;
		timer = setTimeout(() => {
			if (state !== "pressing") return;
			state = "dragging";
			dragging = true;
			try { el.setPointerCapture(pointerId); } catch {}
			navigator.vibrate?.(10);
			onDragStart?.(startX, startY);
		}, LONG_PRESS_MS);
	});

	el.addEventListener("pointermove", (e) => {
		if (state === "pressing") {
			if (Math.hypot(e.clientX - startX, e.clientY - startY) > MOVE_TOLERANCE * scale) reset();
		} else if (state === "dragging") {
			e.preventDefault();
			onDragMove?.(e.clientX, e.clientY);
		}
	});

	el.addEventListener("pointerup", (e) => {
		const was = state;
		reset();
		if (was === "pressing") onTap?.();
		else if (was === "dragging") onDragEnd?.(e.clientX, e.clientY);
	});

	el.addEventListener("pointercancel", (e) => {
		const was = state;
		reset();
		if (was === "dragging") onDragEnd?.(e.clientX, e.clientY);
	});

	// Долгое нажатие не должно вызывать системное меню
	el.addEventListener("contextmenu", (e) => e.preventDefault());
}

/** Попадает ли точка экрана в элемент (с запасом magnet в пикселях макета). */
export function isOver(el, x, y, magnet = 50) {
	const r = el.getBoundingClientRect();
	const m = magnet * scale;
	return x >= r.left - m && x <= r.right + m && y >= r.top - m && y <= r.bottom + m;
}
