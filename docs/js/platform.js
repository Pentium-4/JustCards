// platform.js — работа с файлами телефона (аналог BackupIO и ImagePicker в Godot).

import { MAX_IMAGE_SIZE } from "./data.js";

/** Сохранить резервную копию: меню «Поделиться» → «Сохранить в Файлы». */
export async function saveBackup(text) {
	const date = new Date().toISOString().slice(0, 10);
	const file = new File([text], `just_cards_${date}.json`, { type: "application/json" });
	try {
		if (navigator.canShare?.({ files: [file] })) {
			await navigator.share({ files: [file] });
			return;
		}
	} catch (e) {
		if (e?.name === "AbortError") return; // пользователь закрыл меню
	}
	// Запасной вариант: обычное скачивание.
	const url = URL.createObjectURL(file);
	const a = document.createElement("a");
	a.href = url;
	a.download = file.name;
	document.body.append(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(url), 10000);
}

/** Выбрать файл резервной копии. Возвращает его текст или null. */
export function openBackup() {
	return pickFile("application/json,.json").then((f) => (f ? f.text() : null));
}

/**
 * Выбрать картинку из галереи или «Файлов». Сразу уменьшаем её до 1024 px
 * и поворачиваем правильно (у фото с айфона поворот хранится отдельно).
 * Возвращает JPG-файл (Blob) или null.
 */
export async function pickImage() {
	const file = await pickFile("image/*");
	if (!file) return null;
	try {
		const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
		const k = Math.min(1, MAX_IMAGE_SIZE / Math.max(bitmap.width, bitmap.height));
		const canvas = document.createElement("canvas");
		canvas.width = Math.round(bitmap.width * k);
		canvas.height = Math.round(bitmap.height * k);
		canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
		bitmap.close?.();
		return await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.88));
	} catch (e) {
		console.error("Не удалось прочитать картинку", e);
		return null;
	}
}

function pickFile(accept) {
	return new Promise((resolve) => {
		const input = document.createElement("input");
		input.type = "file";
		input.accept = accept;
		input.onchange = () => resolve(input.files?.[0] ?? null);
		input.oncancel = () => resolve(null);
		input.click();
	});
}
