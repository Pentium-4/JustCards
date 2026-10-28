// Приветственный экран. Умеет только одно: сообщить, что нажали START.

import { h, place, button } from "../ui.js";
import { APP_VERSION } from "../version.js";

export function createStartScreen({ onStart }) {
	const title = place(h("div", { class: "label", style: {
		fontSize: "178px", lineHeight: "200px", flexDirection: "column",
		textShadow: "6px 9px 4px rgba(56, 43, 20, 0.45)",
	} }, h("div", {}, "JUST CARDS"), h("div", {}, "APP")), 0, 818, 1125, 400);

	const start = button({ x: 341, y: 1467, w: 472, h: 154, radius: 50, color: "var(--start)",
		caption: "START", fontSize: 135, onClick: onStart });

	const credits = place(h("div", { class: "label", style: { fontSize: "38px", textShadow: "1px 2px 2px rgba(56,43,20,.45)" } },
		"designed by Nikita Samsygin"), 0, 2246, 1125, 60);
	const version = place(h("div", { class: "label", style: { fontSize: "32px", opacity: 0.75, textShadow: "1px 2px 2px rgba(56,43,20,.45)" } },
		"v" + APP_VERSION), 0, 2300, 1125, 50);

	return [title, start, credits, version];
}
