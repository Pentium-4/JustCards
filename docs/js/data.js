// data.js — AppData: единственное место, где живут данные.
//
// Это прямой аналог scripts/autoload/app_data.gd из Godot-проекта:
// те же функции, те же поля, тот же формат резервной копии. Поэтому копию,
// сделанную на айфоне, можно загрузить на Windows и Android, и наоборот.
//
// Экраны не меняют данные напрямую — они вызывают функции AppData,
// а AppData сохраняет изменения и сообщает об этом событием
// (как сигнал stacks_changed в Godot): AppData.on("stacks_changed", ...).
//
// Хранилище — IndexedDB (встроенная база данных браузера):
//   "kv"     — данные стаков одним объектом;
//   "images" — картинки как файлы (Blob), по имени файла.

const DB_NAME = "just-cards";
const FORMAT_VERSION = 1;
const MAX_IMAGE_SIZE = 1024;
const IMAGE_CACHE_SIZE = 6;

let db = null;
const listeners = {};
let saveTimer = null;

// Готовые ссылки на картинки (object URL), чтобы не читать базу каждый раз.
// Держим только несколько последних — память на телефоне не бесконечна.
const imageUrls = new Map();

export const AppData = {
	/** Все стаки: [{id, name, show_back, loop, cards: [{front: {text, image}, back: {...}}]}] */
	stacks: [],

	// -------------------------------------------------------------------------
	// Запуск
	// -------------------------------------------------------------------------

	async init() {
		db = await openDatabase();
		const saved = await dbGet("kv", "state");
		if (saved) {
			this.stacks = parse(saved) ?? [];
		} else {
			// Первый запуск этой версии: пробуем забрать стаки из прошлой,
			// Godot-версии, которая работала на этом же адресе.
			await migrateFromGodot(this);
		}
		// Просим браузер не удалять наши данные при нехватке места.
		navigator.storage?.persist?.();
	},

	// -------------------------------------------------------------------------
	// События (как сигналы в Godot)
	// -------------------------------------------------------------------------

	on(event, fn) { (listeners[event] ??= []).push(fn); },
	off(event, fn) { listeners[event] = (listeners[event] ?? []).filter((f) => f !== fn); },
	emit(event, ...args) { for (const fn of listeners[event] ?? []) fn(...args); },

	// -------------------------------------------------------------------------
	// Стаки
	// -------------------------------------------------------------------------

	createStack(name) {
		const stack = newStack(name.trim());
		this.stacks.push(stack);
		this._stacksChanged();
		return stack;
	},

	deleteStack(id) {
		const i = this.stacks.findIndex((s) => s.id === id);
		if (i === -1) return;
		for (const card of this.stacks[i].cards) deleteCardImages(card);
		this.stacks.splice(i, 1);
		this._stacksChanged();
	},

	findStack(id) { return this.stacks.find((s) => s.id === id) ?? null; },
	hasStacks() { return this.stacks.length > 0; },

	setShowBack(id, value) { const s = this.findStack(id); if (s) { s.show_back = value; this.queueSave(); } },
	setLoop(id, value) { const s = this.findStack(id); if (s) { s.loop = value; this.queueSave(); } },

	// -------------------------------------------------------------------------
	// Карточки. side — "front" (сторона A) или "back" (сторона B).
	// -------------------------------------------------------------------------

	addCard(id) {
		const s = this.findStack(id);
		s.cards.push(newCard());
		this.queueSave();
		return s.cards.length - 1;
	},

	/** Удаляет карточку. В стаке всегда остаётся хотя бы одна. */
	deleteCard(id, index) {
		const s = this.findStack(id);
		deleteCardImages(s.cards[index]);
		s.cards.splice(index, 1);
		if (s.cards.length === 0) s.cards.push(newCard());
		this.queueSave();
	},

	cardCount(id) { return this.findStack(id)?.cards.length ?? 0; },
	getSide(id, index, side) { return this.findStack(id)?.cards[index]?.[side] ?? newSide(); },

	setCardText(id, index, side, text) {
		const data = this.getSide(id, index, side);
		if (data.text === text) return;
		data.text = text;
		this.queueSave();
	},

	async setCardImage(id, index, side, blob) {
		const data = this.getSide(id, index, side);
		deleteImageFile(data.image);
		const name = makeId() + ".jpg";
		await dbPut("images", name, blob);
		data.image = name;
		this.queueSave();
	},

	removeCardImage(id, index, side) {
		const data = this.getSide(id, index, side);
		deleteImageFile(data.image);
		data.image = "";
		this.queueSave();
	},

	// -------------------------------------------------------------------------
	// Картинки
	// -------------------------------------------------------------------------

	/** Ссылка на картинку для CSS/IMG или null. */
	async imageUrl(name) {
		if (!name) return null;
		if (imageUrls.has(name)) {
			const url = imageUrls.get(name);
			imageUrls.delete(name);
			imageUrls.set(name, url); // снова «свежая»
			return url;
		}
		const blob = await dbGet("images", name);
		if (!blob) return null;
		const url = URL.createObjectURL(blob);
		imageUrls.set(name, url);
		while (imageUrls.size > IMAGE_CACHE_SIZE) {
			const [oldName, oldUrl] = imageUrls.entries().next().value;
			URL.revokeObjectURL(oldUrl);
			imageUrls.delete(oldName);
		}
		return url;
	},

	clearImageCache() {
		for (const url of imageUrls.values()) URL.revokeObjectURL(url);
		imageUrls.clear();
	},

	// -------------------------------------------------------------------------
	// Сохранение
	// -------------------------------------------------------------------------

	/** Сохраняет чуть позже: если изменений много подряд, запись будет одна. */
	queueSave() {
		clearTimeout(saveTimer);
		saveTimer = setTimeout(() => this.saveNow(), 150);
	},

	async saveNow() {
		clearTimeout(saveTimer);
		saveTimer = null;
		await dbPut("kv", "state", toSaveData(this.stacks));
		this.emit("saved");
	},

	_stacksChanged() {
		this.emit("stacks_changed");
		this.queueSave();
	},

	// -------------------------------------------------------------------------
	// Резервная копия — тот же формат, что у Godot-версии
	// -------------------------------------------------------------------------

	async exportBackup() {
		const data = toSaveData(this.stacks);
		data.images = {};
		for (const s of this.stacks) for (const c of s.cards) for (const side of ["front", "back"]) {
			const name = c[side].image;
			if (!name) continue;
			const blob = await dbGet("images", name);
			if (blob) data.images[name] = await blobToBase64(blob);
		}
		return JSON.stringify(data);
	},

	async importBackup(text) {
		let data;
		try { data = JSON.parse(text); } catch { return false; }
		const stacks = parse(data);
		if (!stacks) return false;
		for (const [name, base64] of Object.entries(data.images ?? {})) {
			await dbPut("images", safeName(name), base64ToBlob(base64));
		}
		this.stacks = stacks;
		this.clearImageCache();
		await cleanupUnusedImages(this.stacks);
		this._stacksChanged();
		return true;
	},
};

// Сохраняем сразу, если приложение сворачивают (на айфоне его могут выгрузить).
document.addEventListener("visibilitychange", () => {
	if (document.visibilityState === "hidden" && saveTimer) AppData.saveNow();
});

// ---------------------------------------------------------------------------
// Пустые структуры и проверка данных
// ---------------------------------------------------------------------------

function newSide() { return { text: "", image: "" }; }
function newCard() { return { front: newSide(), back: newSide() }; }
function newStack(name) {
	return { id: makeId(), name, show_back: false, loop: false, cards: [newCard()] };
}
function makeId() {
	return `${Date.now()}_${String(Math.floor(Math.random() * 1e6)).padStart(6, "0")}`;
}
function safeName(name) { return String(name).split(/[\\/]/).pop(); }

function toSaveData(stacks) {
	return { app: "just_cards", version: FORMAT_VERSION, stacks };
}

/** Разбирает и «чинит» данные, как _parse() в Godot. null — если это не наши данные. */
function parse(data) {
	if (!data || !Array.isArray(data.stacks)) return null;
	return data.stacks.filter((s) => s && typeof s === "object").map((raw) => {
		const stack = newStack(String(raw.name ?? ""));
		stack.id = String(raw.id ?? stack.id);
		stack.show_back = Boolean(raw.show_back);
		stack.loop = Boolean(raw.loop);
		const cards = (Array.isArray(raw.cards) ? raw.cards : [])
			.filter((c) => c && typeof c === "object")
			.map((c) => ({ front: parseSide(c.front), back: parseSide(c.back) }));
		stack.cards = cards.length ? cards : [newCard()];
		return stack;
	});
}
function parseSide(raw) {
	const side = newSide();
	if (raw && typeof raw === "object") {
		side.text = String(raw.text ?? "");
		side.image = raw.image ? safeName(raw.image) : "";
	}
	return side;
}

function deleteCardImages(card) {
	deleteImageFile(card.front.image);
	deleteImageFile(card.back.image);
}
function deleteImageFile(name) {
	if (!name) return;
	if (imageUrls.has(name)) { URL.revokeObjectURL(imageUrls.get(name)); imageUrls.delete(name); }
	dbDelete("images", name);
}

async function cleanupUnusedImages(stacks) {
	const used = new Set();
	for (const s of stacks) for (const c of s.cards) { used.add(c.front.image); used.add(c.back.image); }
	for (const name of await dbKeys("images")) if (!used.has(name)) await dbDelete("images", name);
}

// ---------------------------------------------------------------------------
// Перенос данных из Godot-версии
// Godot хранит файлы user:// в базе IndexedDB "/userfs", таблица "FILE_DATA".
// ---------------------------------------------------------------------------

async function migrateFromGodot(app) {
	try {
		if (indexedDB.databases) {
			const list = await indexedDB.databases();
			if (!list.some((d) => d.name === "/userfs")) return;
		}
		const godot = await new Promise((resolve, reject) => {
			const req = indexedDB.open("/userfs");
			req.onsuccess = () => resolve(req.result);
			req.onerror = () => reject(req.error);
		});
		if (!godot.objectStoreNames.contains("FILE_DATA")) { godot.close(); return; }
		const read = (key) => new Promise((resolve) => {
			const req = godot.transaction("FILE_DATA").objectStore("FILE_DATA").get(key);
			req.onsuccess = () => resolve(req.result?.contents ?? null);
			req.onerror = () => resolve(null);
		});
		for (const file of ["/userfs/just_cards.json", "/userfs/just_cards.previous.json"]) {
			const bytes = await read(file);
			if (!bytes) continue;
			const stacks = parse(JSON.parse(new TextDecoder().decode(new Uint8Array(bytes.buffer ?? bytes))));
			if (!stacks) continue;
			for (const s of stacks) for (const c of s.cards) for (const side of ["front", "back"]) {
				const name = c[side].image;
				if (!name) continue;
				const img = await read("/userfs/images/" + name);
				if (img) await dbPut("images", name, new Blob([new Uint8Array(img.buffer ?? img)], { type: "image/jpeg" }));
				else c[side].image = "";
			}
			app.stacks = stacks;
			await app.saveNow();
			break;
		}
		godot.close();
	} catch (e) {
		console.warn("Не удалось перенести данные из Godot-версии", e);
	}
}

// ---------------------------------------------------------------------------
// IndexedDB: маленькие обёртки, чтобы работать через await
// ---------------------------------------------------------------------------

function openDatabase() {
	return new Promise((resolve, reject) => {
		const req = indexedDB.open(DB_NAME, 1);
		req.onupgradeneeded = () => {
			req.result.createObjectStore("kv");
			req.result.createObjectStore("images");
		};
		req.onsuccess = () => resolve(req.result);
		req.onerror = () => reject(req.error);
	});
}
function request(store, mode, fn) {
	return new Promise((resolve, reject) => {
		const req = fn(db.transaction(store, mode).objectStore(store));
		req.onsuccess = () => resolve(req.result);
		req.onerror = () => reject(req.error);
	});
}
const dbGet = (store, key) => request(store, "readonly", (s) => s.get(key));
const dbPut = (store, key, value) => request(store, "readwrite", (s) => s.put(value, key));
const dbDelete = (store, key) => request(store, "readwrite", (s) => s.delete(key));
const dbKeys = (store) => request(store, "readonly", (s) => s.getAllKeys());

function blobToBase64(blob) {
	return new Promise((resolve) => {
		const reader = new FileReader();
		reader.onload = () => resolve(String(reader.result).split(",")[1]);
		reader.readAsDataURL(blob);
	});
}
function base64ToBlob(base64) {
	const bin = atob(base64);
	const bytes = new Uint8Array(bin.length);
	for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
	const isPng = bytes[0] === 0x89 && bytes[1] === 0x50;
	return new Blob([bytes], { type: isPng ? "image/png" : "image/jpeg" });
}

export { MAX_IMAGE_SIZE };
