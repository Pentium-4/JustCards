// Экран карточек одного стака — аналог stack_screen.gd + card_view.gd в Godot.
//
// Как устроено (так же, как в Godot-версии):
//   - данные живут в AppData, экран только показывает их и просит изменить;
//   - при листании старая карточка улетает, новая влетает — это два разных
//     элемента;
//   - порядок показа хранится отдельно от данных, в order. Обычно [0, 1, 2...],
//     после перемешивания — например [2, 0, 1]. Сами карточки в стаке
//     не переставляются, поэтому при выходе порядок «сбрасывается» сам.

import { h, place, button, openLayer, wiggle, scale } from "../ui.js";
import { AppData } from "../data.js";
import { longPress, isOver } from "../gesture.js";
import { askRemove } from "../popups.js";
import { pickImage } from "../platform.js";

const SLIDE_MS = 350;
const FLIP_HALF_MS = 220;
const SWIPE_DISTANCE = 110; // пиксели макета
const WORD_MAX_FONT = 100;
const WORD_MIN_FONT = 46;
const WORD_Y_NO_IMAGE = 656;
const WORD_Y_WITH_IMAGE = 1060;
const EASE_OUT = "cubic-bezier(0.2, 0.8, 0.2, 1)";
const EASE_BACK = "cubic-bezier(0.34, 1.56, 0.64, 1)";
const measure = document.createElement("canvas").getContext("2d"); // для измерения ширины текста

export function openStackScreen(stackId) {
	const layer = openLayer({ blur: true });
	const stack = AppData.findStack(stackId);

	// ---------- Состояние экрана ----------
	let order = stack.cards.map((_, i) => i); // порядок показа
	let position = 0;                         // где мы в order
	let showingBack = stack.show_back;        // какой стороной повёрнута текущая карточка
	let busy = false;                         // идёт анимация — команды игнорируем
	let current = null;                       // текущая карточка: { el, ... }

	const cardIndex = () => order[position];
	const sideName = () => (showingBack ? "back" : "front");
	const currentSide = () => AppData.getSide(stackId, cardIndex(), sideName());
	const isLoop = () => loopBtn.classList.contains("pressed");

	// ---------- Кнопки вокруг карточки ----------
	const holder = h("div", { class: "card-holder" });
	const rotateAllBtn = button({ x: 80, y: 177, w: 326, h: 128, radius: 64, color: "var(--orange-dark)",
		caption: "ROTATE ALL", fontSize: 64, onClick: rotateAll });
	const closeBtn = button({ x: 913, y: 177, w: 133, color: "var(--orange-dark)", icon: "close", iconScale: 0.6, onClick: close });
	const shuffleBtn = button({ x: 244, y: 2110, w: 142, color: "var(--orange-bottom)", icon: "shuffle", iconScale: 0.62, onClick: shuffle });
	const addBtn = button({ x: 463, y: 2079, w: 204, color: "var(--orange)", icon: "close", iconScale: 0.55, rotate: 45, onClick: addCard });
	const loopBtn = button({ x: 743, y: 2110, w: 142, color: "var(--orange-bottom)", icon: "loop", iconScale: 0.8, onClick: toggleLoop });
	loopBtn.classList.toggle("pressed", stack.loop);

	const content = h("div", { class: "pop", style: { position: "absolute", inset: 0 } },
		holder, rotateAllBtn, closeBtn, shuffleBtn, addBtn, loopBtn);
	layer.frame.append(content);
	layer.onCancel = close;

	current = createCard();
	holder.append(current.el);

	// =========================================================================
	// Карточка
	// =========================================================================

	function createCard() {
		const el = h("div", { class: "card" });
		const addImageBtn = button({ x: 118, y: 98, w: 243, h: 216, radius: 28, color: "var(--mint)",
			icon: "add_image", iconScale: 1.13, onClick: onAddImage });
		const trashBtn = button({ x: 754, y: 98, w: 115, color: "var(--red)", icon: "trash", iconScale: 0.7, onClick: onDeleteCard });
		const image = place(h("div", { class: "image-frame" }), 118, 291, 726, 726);
		const word = place(h("input", { class: "field word", type: "text", placeholder: "WORD", maxlength: "60",
			autocomplete: "off", autocorrect: "off", spellcheck: "false" }), 120, WORD_Y_NO_IMAGE, 726, 132);
		const prevBtn = button({ x: 85, y: 1321, w: 140, h: 220, flat: true, icon: "arrow_left", iconScale: 1.72,
			iconColor: "var(--orange-light)", onClick: () => go(-1) });
		const nextBtn = button({ x: 737, y: 1319, w: 140, h: 220, flat: true, icon: "arrow_right", iconScale: 1.72,
			iconColor: "var(--orange-light)", onClick: () => go(1) });
		const flipBtn = button({ x: 370, y: 1316, w: 225, color: "var(--orange-light)", icon: "rotate", iconScale: 0.56, onClick: flip });
		el.append(addImageBtn, trashBtn, image, word, prevBtn, nextBtn, flipBtn);

		const card = { el, addImageBtn, trashBtn, image, word, prevBtn, nextBtn, imageDragging: false };

		word.addEventListener("input", () => {
			fitWord(word);
			AppData.setCardText(stackId, cardIndex(), sideName(), word.value);
		});

		// Свайп по карточке (и нажатие мимо поля — прячем клавиатуру)
		let swipeStart = null;
		el.addEventListener("pointerdown", (e) => {
			if (e.target.closest("button, input")) return;
			word.blur();
			swipeStart = { x: e.clientX, y: e.clientY };
		});
		el.addEventListener("pointerup", (e) => {
			if (!swipeStart || card.imageDragging) { swipeStart = null; return; }
			const dx = (e.clientX - swipeStart.x) / scale;
			const dy = (e.clientY - swipeStart.y) / scale;
			swipeStart = null;
			if (Math.abs(dx) > SWIPE_DISTANCE && Math.abs(dx) > Math.abs(dy) * 1.2) go(dx < 0 ? 1 : -1);
		});

		setupImageDrag(card);
		showSide(card, currentSide());
		updateNavigation(card, false);
		return card;
	}

	async function showSide(card, side) {
		card.word.value = side.text;
		fitWord(card.word);
		const url = await AppData.imageUrl(side.image);
		card.image.style.backgroundImage = url ? `url("${url}")` : "";
		card.image.style.display = url ? "" : "none";
		card.addImageBtn.style.display = url ? "none" : "";
		card.word.style.top = (url ? WORD_Y_WITH_IMAGE : WORD_Y_NO_IMAGE) + "px";
	}

	// Длинные слова уменьшаются, чтобы влезть в поле.
	function fitWord(input) {
		measure.font = `${WORD_MAX_FONT}px Abel, "JC Cyrillic", "JC Georgian", sans-serif`;
		const width = measure.measureText(input.value).width;
		const available = 726 - 70;
		const size = width > available ? Math.max(WORD_MIN_FONT, Math.floor(WORD_MAX_FONT * available / width)) : WORD_MAX_FONT;
		input.style.fontSize = size + "px";
	}

	// Стрелки видны, если карточек больше одной. Без повтора на краях исчезают.
	function updateNavigation(card, animated = true) {
		const count = order.length;
		const showPrev = count > 1 && (isLoop() || position > 0);
		const showNext = count > 1 && (isLoop() || position < count - 1);
		for (const [btn, show] of [[card.prevBtn, showPrev], [card.nextBtn, showNext]]) {
			if (!animated) btn.style.transition = "none";
			btn.classList.toggle("hidden", !show);
			if (!animated) requestAnimationFrame(() => (btn.style.transition = ""));
		}
	}

	// =========================================================================
	// Листание
	// =========================================================================

	function go(direction) {
		if (busy || order.length < 2) return;
		let next = position + direction;
		if (isLoop()) next = (next + order.length) % order.length;
		else if (next < 0 || next >= order.length) return bounce(direction);
		position = next;
		showingBack = stack.show_back;
		replaceCard(direction > 0 ? "next" : "prev");
	}

	/** Заменяет карточку на новую с анимацией: "next" | "prev" | "add" | "delete" | "shuffle". */
	async function replaceCard(how) {
		busy = true;
		const old = current;
		old.word.blur();
		old.el.style.pointerEvents = "none";
		current = createCard();
		const el = current.el;
		const anims = [];

		if (how === "delete") {
			holder.insertBefore(el, old.el);
			anims.push(old.el.animate([{ transform: "scale(1)", opacity: 1 }, { transform: "scale(0.6)", opacity: 0 }],
				{ duration: SLIDE_MS, easing: "ease-in", fill: "forwards" }));
			anims.push(el.animate([{ transform: "scale(0.92)", opacity: 0 }, { transform: "scale(1)", opacity: 1 }],
				{ duration: SLIDE_MS, delay: 150, easing: EASE_OUT, fill: "backwards" }));
		} else if (how === "add") {
			holder.append(el);
			anims.push(el.animate([{ transform: "translateY(2600px)" }, { transform: "translateY(0)" }],
				{ duration: SLIDE_MS + 100, easing: EASE_BACK }));
		} else {
			holder.append(el);
			const s = how === "prev" ? -1 : 1;
			anims.push(el.animate([{ transform: `translateX(${1300 * s}px) rotate(${10 * s}deg)` }, { transform: "none" }],
				{ duration: SLIDE_MS, easing: EASE_OUT }));
			anims.push(old.el.animate([{ transform: "none" }, { transform: `translateX(${-1300 * s}px) rotate(${-10 * s}deg)` }],
				{ duration: SLIDE_MS, easing: EASE_OUT, fill: "forwards" }));
		}
		await Promise.all(anims.map((a) => a.finished));
		old.el.remove();
		busy = false;
	}

	async function bounce(direction) {
		busy = true;
		await current.el.animate([{ transform: "none" }, { transform: `translateX(${-40 * direction}px)` }, { transform: "none" }],
			{ duration: 350, easing: "ease-out" }).finished;
		busy = false;
	}

	// =========================================================================
	// Переворот «волчком» по часовой стрелке
	// =========================================================================

	async function flip() {
		if (busy) return;
		busy = true;
		showingBack = !showingBack;
		const card = current;
		card.word.blur();
		// Первая половина: карточка поворачивается ребром…
		await card.el.animate([{ transform: "rotateY(0deg)" }, { transform: "rotateY(90deg)" }],
			{ duration: FLIP_HALF_MS, easing: "ease-in", fill: "forwards" }).finished;
		// …в этот момент подменяем сторону (этого не видно)…
		await showSide(card, currentSide());
		// …и новая сторона доворачивается к нам.
		await card.el.animate([{ transform: "rotateY(-90deg)" }, { transform: "rotateY(0deg)" }],
			{ duration: FLIP_HALF_MS, easing: "ease-out" }).finished;
		card.el.getAnimations().forEach((a) => a.cancel());
		busy = false;
	}

	// =========================================================================
	// Кнопки
	// =========================================================================

	// ROTATE ALL: переключает режим стака, текущая карточка поворачивается к нему.
	function rotateAll() {
		if (busy) return;
		stack.show_back = !stack.show_back;
		AppData.setShowBack(stackId, stack.show_back);
		if (showingBack !== stack.show_back) flip();
	}

	function addCard() {
		if (busy) return;
		const newIndex = AppData.addCard(stackId);
		position = Math.min(position + 1, order.length);
		order.splice(position, 0, newIndex);
		showingBack = stack.show_back;
		replaceCard("add");
	}

	function shuffle() {
		if (busy || order.length < 2) return wiggle(shuffleBtn);
		for (let i = order.length - 1; i > 0; i--) {
			const j = Math.floor(Math.random() * (i + 1));
			[order[i], order[j]] = [order[j], order[i]];
		}
		position = 0;
		showingBack = stack.show_back;
		replaceCard("shuffle");
	}

	function toggleLoop() {
		const on = !isLoop();
		loopBtn.classList.toggle("pressed", on);
		AppData.setLoop(stackId, on);
		updateNavigation(current);
	}

	async function onDeleteCard() {
		if (busy || !(await askRemove())) return;
		const removed = cardIndex();
		AppData.deleteCard(stackId, removed);
		// Убираем номер из порядка показа, номера после него сдвигаем на 1.
		order.splice(position, 1);
		order = order.map((i) => (i > removed ? i - 1 : i));
		if (order.length === 0) order.push(0); // стак не бывает пустым
		position = Math.min(position, order.length - 1);
		showingBack = stack.show_back;
		replaceCard("delete");
	}

	// =========================================================================
	// Картинки
	// =========================================================================

	async function onAddImage() {
		const target = { index: cardIndex(), side: sideName() };
		const blob = await pickImage();
		if (!blob) return;
		await AppData.setCardImage(stackId, target.index, target.side, blob);
		if (target.index === cardIndex() && target.side === sideName()) showSide(current, currentSide());
	}

	// Перенос картинки в корзину: долгое нажатие и перетаскивание
	function setupImageDrag(card) {
		let ghost = null, ox = 0, oy = 0, rect = null, over = false;
		const transform = (x, y, k) => `translate(${x - ox}px, ${y - oy}px) scale(${k})`;

		longPress(card.image, {
			onDragStart: (x, y) => {
				card.imageDragging = true;
				card.word.blur();
				rect = card.image.getBoundingClientRect();
				ox = x - rect.left; oy = y - rect.top;
				ghost = h("div", { class: "image-ghost" });
				Object.assign(ghost.style, {
					width: rect.width + "px", height: rect.height + "px",
					backgroundImage: card.image.style.backgroundImage,
					borderRadius: 30 * scale + "px",
					transformOrigin: `${ox}px ${oy}px`,
					transform: transform(x, y, 1),
					transition: "transform 0.2s " + EASE_BACK,
				});
				document.body.append(ghost);
				card.image.classList.add("dimmed");
				requestAnimationFrame(() => (ghost.style.transform = transform(x, y, 0.4)));
				over = false;
			},
			onDragMove: (x, y) => {
				if (!ghost) return;
				const nowOver = isOver(card.trashBtn, x, y, 60);
				ghost.style.transition = "transform 0.06s linear";
				ghost.style.transform = transform(x, y, nowOver ? 0.25 : 0.4);
				if (nowOver !== over) {
					over = nowOver;
					card.trashBtn.style.transform = over ? "scale(1.3)" : "";
				}
			},
			onDragEnd: async (x, y) => {
				if (!ghost) return;
				card.trashBtn.style.transform = "";
				const g = ghost;
				ghost = null;
				const remove = isOver(card.trashBtn, x, y, 60) && (await askRemove());
				g.style.transition = "transform 0.3s " + EASE_OUT + ", opacity 0.25s";
				if (remove) {
					g.style.transform = transform(x, y, 0.01);
					g.style.opacity = 0;
					AppData.removeCardImage(stackId, cardIndex(), sideName());
					showSide(card, currentSide());
				} else {
					g.style.transform = transform(rect.left + ox, rect.top + oy, 1);
				}
				setTimeout(() => { g.remove(); card.image.classList.remove("dimmed"); card.imageDragging = false; }, 320);
			},
		});
	}

	// =========================================================================
	// Клавиатура на ПК и закрытие
	// =========================================================================

	function onKey(e) {
		if (document.activeElement?.tagName === "INPUT") return;
		if (e.key === "ArrowLeft") go(-1);
		else if (e.key === "ArrowRight") go(1);
	}
	document.addEventListener("keydown", onKey);

	function close() {
		document.removeEventListener("keydown", onKey);
		current.word.blur();
		AppData.saveNow();
		layer.close().then(() => AppData.clearImageCache());
	}
}
