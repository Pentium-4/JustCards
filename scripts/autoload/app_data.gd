extends Node
## AppData — единственное место, где живут данные приложения.
##
## По роли это как GameInstance в Unreal: существует всё время работы
## приложения, и к нему можно обратиться из любого скрипта по имени: AppData.
## (В Godot такие скрипты называются Autoload, они подключены в
## Project > Project Settings > Globals.)
##
## Главное правило архитектуры: экраны НЕ меняют данные напрямую.
## Они вызывают функции этого скрипта (create_stack, delete_stack...),
## а он меняет данные, сохраняет их и отправляет сигнал stacks_changed.
## Экраны подписаны на сигнал и сами обновляют свой вид.
## Сигнал — это аналог Event Dispatcher в Blueprints.

## Отправляется после любого изменения стаков: создали, удалили, переименовали,
## загрузили из резервной копии.
signal stacks_changed

## Файл с данными. "user://" — личная папка приложения:
## на Windows это %APPDATA%\Godot\app_userdata\Just Cards,
## в браузере — встроенное хранилище браузера (IndexedDB).
const SAVE_PATH := "user://just_cards.json"
## Предыдущая версия сохранения, на случай если основной файл повредится.
const PREVIOUS_SAVE_PATH := "user://just_cards.previous.json"
const TEMP_SAVE_PATH := "user://just_cards.tmp"

## Версия формата файла. Пригодится, если мы когда-нибудь поменяем
## структуру данных: по номеру будет понятно, как читать старые файлы.
const FORMAT_VERSION := 1

## Все стаки. Каждый стак — это Dictionary (по смыслу как Struct в Blueprints):
## {
##     "id": "уникальная строка",
##     "name": "название стака",
##     "show_back": false,   # режим ROTATE ALL: true = карточки открываются стороной B
##     "cards": [ карточка, карточка, ... ]
## }
## Карточка: { "front": сторона, "back": сторона }
## Сторона:  { "text": "слово", "image": "" }   # image — имя файла картинки (этап 3)
var stacks: Array[Dictionary] = []

var _save_queued := false


func _ready() -> void:
	load_from_disk()
	_request_persistent_storage()


# ---------------------------------------------------------------------------
# Создание пустых структур
# ---------------------------------------------------------------------------

static func new_side() -> Dictionary:
	return {"text": "", "image": ""}


static func new_card() -> Dictionary:
	return {"front": new_side(), "back": new_side()}


static func new_stack(stack_name: String) -> Dictionary:
	return {
		"id": _make_id(),
		"name": stack_name,
		"show_back": false,
		# По дизайну в новом стаке сразу есть одна пустая карточка.
		"cards": [new_card()],
	}


static func _make_id() -> String:
	# Время в миллисекундах + случайное число: двух одинаковых не будет.
	return "%d_%06d" % [Time.get_unix_time_from_system() * 1000.0, randi() % 1000000]


# ---------------------------------------------------------------------------
# Работа со стаками. Экраны вызывают только эти функции.
# ---------------------------------------------------------------------------

func create_stack(stack_name: String) -> Dictionary:
	var stack := new_stack(stack_name.strip_edges())
	stacks.append(stack)
	_changed()
	return stack


func delete_stack(stack_id: String) -> void:
	var index := _find_index(stack_id)
	if index == -1:
		return
	stacks.remove_at(index)
	_changed()


func rename_stack(stack_id: String, new_name: String) -> void:
	var stack := find_stack(stack_id)
	if stack.is_empty():
		return
	stack["name"] = new_name.strip_edges()
	_changed()


## Возвращает стак по id или пустой Dictionary, если такого нет.
func find_stack(stack_id: String) -> Dictionary:
	var index := _find_index(stack_id)
	return stacks[index] if index != -1 else {}


func has_stacks() -> bool:
	return not stacks.is_empty()


func _find_index(stack_id: String) -> int:
	for i in stacks.size():
		if stacks[i].get("id") == stack_id:
			return i
	return -1


## Вызывается после каждого изменения: сообщаем экранам и сохраняем.
func _changed() -> void:
	stacks_changed.emit()
	queue_save()


# ---------------------------------------------------------------------------
# Сохранение на диск (автоматическое)
# ---------------------------------------------------------------------------

## Просим сохранить. Само сохранение произойдёт в конце текущего кадра:
## если за один кадр случилось несколько изменений, файл запишется один раз.
func queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_save_now.call_deferred()


func _save_now() -> void:
	_save_queued = false
	var text := JSON.stringify(_to_save_data(), "\t")

	# Безопасная запись в три шага, чтобы не потерять данные,
	# если запись оборвётся на середине (например, выключится свет):
	# 1) пишем во временный файл;
	var file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось сохранить данные: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(text)
	file.close()
	# 2) старое сохранение переименовываем в «предыдущее»;
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(SAVE_PATH, PREVIOUS_SAVE_PATH)
	# 3) временный файл становится основным.
	DirAccess.rename_absolute(TEMP_SAVE_PATH, SAVE_PATH)


func load_from_disk() -> void:
	# Сначала пробуем основной файл, если он повреждён — предыдущий.
	for path in [SAVE_PATH, PREVIOUS_SAVE_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var loaded: Variant = _parse(FileAccess.get_file_as_string(path))
		if loaded != null:
			stacks = loaded
			stacks_changed.emit()
			return
		push_warning("Файл %s повреждён, пробую следующий" % path)


func _to_save_data() -> Dictionary:
	return {"app": "just_cards", "version": FORMAT_VERSION, "stacks": stacks}


## Разбирает текст сохранения. Возвращает список стаков или null, если текст
## не похож на наши данные. Заодно «чинит» данные: добавляет недостающие поля,
## чтобы остальной код мог на них полагаться.
func _parse(text: String) -> Variant:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("stacks")) != TYPE_ARRAY:
		return null
	var result: Array[Dictionary] = []
	for raw in data["stacks"]:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var stack := new_stack(str(raw.get("name", "")))
		stack["id"] = str(raw.get("id", stack["id"]))
		stack["show_back"] = bool(raw.get("show_back", false))
		var cards: Array = []
		for raw_card in raw.get("cards", []):
			if typeof(raw_card) == TYPE_DICTIONARY:
				cards.append({
					"front": _parse_side(raw_card.get("front")),
					"back": _parse_side(raw_card.get("back")),
				})
		stack["cards"] = cards if not cards.is_empty() else [new_card()]
		result.append(stack)
	return result


func _parse_side(raw: Variant) -> Dictionary:
	var side := new_side()
	if typeof(raw) == TYPE_DICTIONARY:
		side["text"] = str(raw.get("text", ""))
		side["image"] = str(raw.get("image", ""))
	return side


# ---------------------------------------------------------------------------
# Резервная копия (кнопка сохранить / загрузить)
# ---------------------------------------------------------------------------

## Весь архив стаков одним текстом. На этапе с картинками сюда же
## добавятся сами картинки, чтобы копия была полной.
func export_backup_text() -> String:
	return JSON.stringify(_to_save_data(), "\t")


## Загружает стаки из текста резервной копии. Возвращает false,
## если файл не похож на копию Just Cards.
func import_backup_text(text: String) -> bool:
	var loaded: Variant = _parse(text)
	if loaded == null:
		return false
	stacks = loaded
	_changed()
	return true


# ---------------------------------------------------------------------------
# Только для браузера
# ---------------------------------------------------------------------------

## Просим браузер считать наше хранилище «постоянным»: тогда система не будет
## удалять данные при нехватке места. От ручной очистки Safari это не спасает.
func _request_persistent_storage() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.storage && navigator.storage.persist && navigator.storage.persist();", true)


func _notification(what: int) -> void:
	# Если приложение закрывают или сворачивают, а сохранение ещё ждёт
	# конца кадра, сохраняем немедленно.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _save_queued:
			_save_now()
