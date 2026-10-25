extends Node
## BackupIO — сохранение и открытие файла резервной копии.
##
## На Windows и в браузере айфона это два совсем разных механизма:
## - Windows: обычное окно «Сохранить как» / «Открыть».
## - Браузер: меню «Поделиться» айфона (там есть «Сохранить в Файлы»)
##   и системный выбор файла. Это делается через JavaScript.
##
## Остальной код об этой разнице не знает: он просто вызывает
## BackupIO.save_backup(текст) или BackupIO.open_backup() и ждёт сигнал.
## Такой приём (спрятать различия платформ за одной функцией) пригодится
## и дальше — на этапе с картинками сделаем так же.

## Отправляется, когда пользователь выбрал файл копии. text — его содержимое.
signal backup_loaded(text: String)

const FILE_FILTER := "*.json ; Just Cards backup"

# Код для браузера. Он выполняется один раз при запуске и создаёт
# в JavaScript объект window.justCards с двумя функциями.
const WEB_HELPERS_JS := """
window.justCards = {
	saveFile: async function (text, filename) {
		const file = new File([text], filename, { type: "application/json" });
		try {
			if (navigator.canShare && navigator.canShare({ files: [file] })) {
				await navigator.share({ files: [file] });
				return;
			}
		} catch (e) {
			if (e && e.name === "AbortError") return; // пользователь закрыл меню
		}
		// Запасной вариант: обычное скачивание файла.
		const url = URL.createObjectURL(file);
		const a = document.createElement("a");
		a.href = url;
		a.download = filename;
		document.body.appendChild(a);
		a.click();
		a.remove();
		setTimeout(() => URL.revokeObjectURL(url), 10000);
	},
	openFile: function (callback) {
		const input = document.createElement("input");
		input.type = "file";
		input.accept = "application/json,.json";
		input.onchange = () => {
			const f = input.files && input.files[0];
			if (f) f.text().then((t) => callback(t));
		};
		input.click();
	},
};
"""

var _web_load_callback: JavaScriptObject # ссылку нужно хранить, иначе её удалит сборщик мусора
var _dialog: FileDialog


func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(WEB_HELPERS_JS, true)
		_web_load_callback = JavaScriptBridge.create_callback(_on_web_file_loaded)


## Сохранить текст копии в файл, выбранный пользователем.
func save_backup(text: String) -> void:
	var filename := "just_cards_%s.json" % Time.get_date_string_from_system()
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("justCards").saveFile(text, filename)
	else:
		_show_dialog(FileDialog.FILE_MODE_SAVE_FILE, filename, func(path: String):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_string(text)
		)


## Попросить пользователя выбрать файл копии. Результат придёт сигналом backup_loaded.
func open_backup() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("justCards").openFile(_web_load_callback)
	else:
		_show_dialog(FileDialog.FILE_MODE_OPEN_FILE, "", func(path: String):
			backup_loaded.emit(FileAccess.get_file_as_string(path))
		)


func _on_web_file_loaded(args: Array) -> void:
	backup_loaded.emit(str(args[0]))


## Показывает системное окно выбора файла Windows.
func _show_dialog(mode: FileDialog.FileMode, default_name: String, on_selected: Callable) -> void:
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.use_native_dialog = true
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = mode
	_dialog.filters = PackedStringArray([FILE_FILTER])
	_dialog.current_file = default_name
	_dialog.file_selected.connect(on_selected)
	add_child(_dialog)
	_dialog.popup_centered()
