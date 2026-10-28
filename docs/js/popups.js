// popups.js — попапы: создание стака и «REMOVE?».
//
// Как и в Godot-версии, попап ничего не решает сам. Он возвращает ответ
// (Promise), а что делать с ответом — решает экран, который его открыл.

import { h, place, button, openLayer } from "./ui.js";

/** Попап создания стака. Возвращает название или null, если отменили. */
export function askStackName() {
	return new Promise((resolve) => {
		const layer = openLayer({ blur: true });
		const panel = place(h("div", { class: "panel pop" }), 123, 795, 879, 715);

		const input = place(h("input", {
			class: "field", type: "text", placeholder: "stack name", maxlength: "40",
			autocomplete: "off", autocorrect: "off", spellcheck: "false",
		}), 109, 259, 662, 118);
		input.style.fontSize = "96px";

		const finish = (value) => { layer.close(); resolve(value); };
		const confirm = button({ x: 358, y: 470, w: 165, color: "var(--orange-light)", icon: "check", iconScale: 0.62,
			onClick: () => { if (input.value.trim()) finish(input.value.trim()); } });
		const cancel = button({ x: 700, y: 74, w: 105, color: "var(--red)", icon: "trash", iconScale: 0.7,
			onClick: () => finish(null) });

		// Пока название пустое, галочка неактивна.
		const update = () => confirm.classList.toggle("disabled", !input.value.trim());
		input.addEventListener("input", update);
		input.addEventListener("keydown", (e) => { if (e.key === "Enter") confirm.click(); });
		update();

		panel.append(cancel, input, confirm);
		layer.frame.append(panel);
		layer.onCancel = () => finish(null);
		// Клавиатура на айфоне открывается только от нажатия пользователя,
		// поэтому фокус ставим сразу, в том же нажатии, что открыло попап.
		input.focus();
	});
}

/** Попап «REMOVE?». Возвращает true (да) или false (нет). */
export function askRemove(question = "REMOVE?") {
	return new Promise((resolve) => {
		const layer = openLayer({ blur: true });
		const panel = place(h("div", { class: "panel pop" }), 123, 795, 879, 715);
		const plate = place(h("div", { class: "label", style: {
			background: "var(--plate-grey)", borderRadius: "25px", fontSize: "100px",
			boxShadow: "4px 6px 8px rgba(64, 51, 25, 0.3)",
		} }, question), 109, 259, 662, 118);

		const finish = (yes) => { layer.close(); resolve(yes); };
		panel.append(
			plate,
			button({ x: 211, y: 470, w: 165, color: "var(--green)", icon: "check", iconScale: 0.62, onClick: () => finish(true) }),
			button({ x: 502, y: 470, w: 165, color: "var(--red)", icon: "close", iconScale: 0.55, onClick: () => finish(false) }),
		);
		layer.frame.append(panel);
		layer.onCancel = () => finish(false);
	});
}
