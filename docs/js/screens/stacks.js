// Главный экран: таблица стаков, «+», корзина и кнопка резервной копии.
//
// Как в Godot-версии: экран берёт данные из AppData, подписан на событие
// stacks_changed и сообщает наружу onOpenStack(id). Про экран карточек
// он ничего не знает.

import { h, button, setButtonIcon, wiggle, scale } from "../ui.js";
import { AppData } from "../data.js";
import { longPress, isOver } from "../gesture.js";
import { askStackName, askRemove } from "../popups.js";
import { saveBackup, openBackup } from "../platform.js";

const SAVE_COLOR = "var(--red-top)";
const LOAD_COLOR = "rgba(252, 123, 79, 0.7)";

export function createStacksScreen(layer, { onOpenStack }) {
	// ---------- Разметка ----------
	const addTile = button({ x: 0, y: 0, w: 240, radius: 45, color: "var(--add-stack)",
		icon: "plus", iconScale: 0.72, onClick: createStack });
	addTile.style.position = "relative";
	addTile.style.left = addTile.style.top = "";

	const grid = h("div", { class: "grid" }, addTile);
	const scroll = h("div", { class: "scroll" }, grid);
	const thumb = h("div", { class: "thumb" });
	const scrollbar = h("div", { class: "scrollbar" }, thumb);
	const column = h("div", { class: "column" }, scroll, scrollbar);

	const backupBtn = button({ x: 80, y: 167, w: 130, color: SAVE_COLOR, icon: "save", iconScale: 0.62, onClick: onBackupPressed });
	// Левый край кнопки сохранения и правый край корзины совпадают с краями сетки (поля по 80).
	const trashBtn = button({ x: 915, y: 167, w: 130, color: "var(--red-top)", icon: "trash", iconScale: 0.7,
		onClick: () => wiggle(trashBtn) }); // в корзину тащат, а не нажимают

	layer.stage.insertBefore(column, layer.frame);
	layer.frame.append(backupBtn, trashBtn);

	// ---------- Таблица ----------
	function rebuild() {
		for (const tile of [...grid.querySelectorAll(".tile")]) tile.remove();
		for (const stack of AppData.stacks) grid.append(createTile(stack));
		updateBackupButton();
		requestAnimationFrame(updateScrollbar);
	}

	function createTile(stack) {
		const tile = h("div", { class: "tile" },
			h("div", { class: "back back2" }),
			h("div", { class: "back back1" }),
			h("div", { class: "front" }, h("div", { class: "label name" }, stack.name)),
		);
		tile.dataset.id = stack.id;
		longPress(tile, {
			onTap: () => onOpenStack(stack.id),
			onDragStart: (x, y) => startDrag(tile, x, y),
			onDragMove: (x, y) => moveDrag(x, y),
			onDragEnd: (x, y) => endDrag(x, y),
		});
		return tile;
	}

	async function createStack() {
		const name = await askStackName();
		if (!name) return;
		const stack = AppData.createStack(name);
		const tile = grid.querySelector(`.tile[data-id="${stack.id}"]`);
		tile?.classList.add("pop-in");
		tile?.scrollIntoView({ behavior: "smooth", block: "nearest" });
		onOpenStack(stack.id);
	}

	// ---------- Ползунок справа ----------
	function updateScrollbar() {
		const { scrollHeight, clientHeight, scrollTop } = scroll;
		const visible = scrollHeight > clientHeight + 1;
		scrollbar.style.opacity = visible ? 1 : 0;
		if (!visible) return;
		const track = scrollbar.clientHeight;
		const thumbH = Math.max(120, track * clientHeight / scrollHeight);
		thumb.style.height = thumbH + "px";
		thumb.style.top = (track - thumbH) * scrollTop / (scrollHeight - clientHeight) + "px";
	}
	scroll.addEventListener("scroll", updateScrollbar, { passive: true });
	window.addEventListener("resize", updateScrollbar);

	// Ползунок можно тащить пальцем
	thumb.addEventListener("pointerdown", (e) => {
		const startY = e.clientY, startTop = scroll.scrollTop;
		thumb.setPointerCapture(e.pointerId);
		const move = (ev) => {
			const range = (scrollbar.clientHeight - thumb.clientHeight) * scale;
			scroll.scrollTop = startTop + (ev.clientY - startY) / range * (scroll.scrollHeight - scroll.clientHeight);
		};
		const up = () => { thumb.removeEventListener("pointermove", move); thumb.removeEventListener("pointerup", up); };
		thumb.addEventListener("pointermove", move);
		thumb.addEventListener("pointerup", up);
	});

	// ---------- Перенос плитки в корзину ----------
	let drag = null; // { tile, ghost, offX, offY, overTrash }
	const GHOST_LIFT = 1.12;

	function ghostTransform(x, y, k) {
		// x, y — где должен быть центр плитки (пиксели экрана)
		const half = 120 * scale * k;
		return `translate(${x - half}px, ${y - half}px) scale(${scale * k})`;
	}

	function startDrag(tile, x, y) {
		const r = tile.getBoundingClientRect();
		const ghost = tile.cloneNode(true);
		ghost.classList.add("ghost");
		document.body.append(ghost);
		drag = { tile, ghost, offX: r.left + r.width / 2 - x, offY: r.top + r.height / 2 - y, overTrash: false, x, y };
		tile.classList.add("dimmed");
		scroll.style.overflowY = "hidden"; // пока тащим, список стоит
		ghost.style.transform = ghostTransform(x + drag.offX, y + drag.offY, 1);
		ghost.animate([{ transform: ghostTransform(x + drag.offX, y + drag.offY, 1) },
			{ transform: ghostTransform(x + drag.offX, y + drag.offY, GHOST_LIFT) }], { duration: 150, fill: "forwards" })
			.finished.then(() => drag && moveDrag(drag.x, drag.y));
	}

	function moveDrag(x, y) {
		if (!drag) return;
		drag.x = x; drag.y = y;
		const over = isOver(trashBtn, x, y);
		drag.ghost.getAnimations().forEach((a) => a.cancel());
		drag.ghost.style.transition = "transform 0.05s linear";
		drag.ghost.style.transform = ghostTransform(x + drag.offX, y + drag.offY, over ? 0.8 : GHOST_LIFT);
		if (over !== drag.overTrash) {
			drag.overTrash = over;
			trashBtn.style.transform = over ? "scale(1.25)" : "";
		}
	}

	async function endDrag(x, y) {
		if (!drag) return;
		const d = drag;
		trashBtn.style.transform = "";
		if (isOver(trashBtn, x, y) && await askRemove()) {
			drag = null;
			d.ghost.style.transition = "transform 0.25s ease-in, opacity 0.25s";
			d.ghost.style.transform = ghostTransform(x + d.offX, y + d.offY, 0.01);
			d.ghost.style.opacity = 0;
			setTimeout(() => d.ghost.remove(), 260);
			AppData.deleteStack(d.tile.dataset.id);
		} else {
			// Плитка возвращается на место
			drag = null;
			const r = d.tile.getBoundingClientRect();
			d.ghost.style.transition = "transform 0.3s cubic-bezier(0.2, 0.8, 0.2, 1)";
			d.ghost.style.transform = ghostTransform(r.left + r.width / 2, r.top + r.height / 2, 1);
			setTimeout(() => { d.ghost.remove(); d.tile.classList.remove("dimmed"); }, 310);
		}
		scroll.style.overflowY = "";
	}

	// ---------- Резервная копия: одна кнопка, которая сама решает, что показать ----------
	let showsSave = null;
	function updateBackupButton() {
		const save = AppData.hasStacks();
		if (save === showsSave) return;
		const first = showsSave === null;
		showsSave = save;
		const apply = () => {
			setButtonIcon(backupBtn, save ? "save" : "load");
			backupBtn.style.setProperty("--c", save ? SAVE_COLOR : LOAD_COLOR);
		};
		if (first) return apply();
		backupBtn.animate([{ transform: "scale(1)" }, { transform: "scale(0)" }], { duration: 150, easing: "ease-in" })
			.finished.then(() => {
				apply();
				backupBtn.animate([{ transform: "scale(0)" }, { transform: "scale(1)" }],
					{ duration: 300, easing: "cubic-bezier(0.34, 1.56, 0.64, 1)" });
			});
	}

	// Айфон разрешает открыть меню «Поделиться» только сразу после нажатия.
	// Поэтому копию готовим заранее, после каждого сохранения, а по нажатию
	// просто отдаём готовый текст.
	let preparedBackup = null;
	let preparing = 0;
	async function prepareBackup() {
		const ticket = ++preparing;
		const text = await AppData.exportBackup();
		if (ticket === preparing) preparedBackup = text;
	}
	AppData.on("saved", prepareBackup);
	prepareBackup();

	async function onBackupPressed() {
		if (AppData.hasStacks()) {
			await saveBackup(preparedBackup ?? await AppData.exportBackup());
		} else {
			const text = await openBackup();
			if (text && !(await AppData.importBackup(text))) wiggle(backupBtn); // файл не подошёл
		}
	}

	AppData.on("stacks_changed", rebuild);
	rebuild();
}
