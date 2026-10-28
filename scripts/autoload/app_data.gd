extends Node
## AppData — единственное место, где живут данные приложения.
##
## По роли это как GameInstance в Unreal: существует всё время работы
## приложения, и к нему можно обратиться из любого скрипта по имени: AppData.
## (В Godot такие скрипты называются Autoload, они подключены в
## Project > Project Settings > Globals.)
##
## Главное правило архитектуры: экраны НЕ меняют данные напрямую.
## Они вызывают функции этого скрипта (create_stack, add_card...),
## а он меняет данные, сохраняет их и отправляет сигнал.
## Экраны подписаны на сигналы и сами обновляют свой вид.
## Сигнал — это аналог Event Dispatcher в Blueprints.

## Изменился список стаков: создали, удалили, переименовали, загрузили копию.
signal stacks_changed
## Изменились карточки внутри стака (текст, картинка, количество).
signal cards_changed(stack_id: String)

## Файл с данными. "user://" — личная папка приложения:
## на Windows это %APPDATA%\Godot\app_userdata\Just Cards,
## в браузере — встроенное хранилище браузера (IndexedDB).
const SAVE_PATH := "user://just_cards.json"
## Предыдущая версия сохранения, на случай если основной файл повредится.
const PREVIOUS_SAVE_PATH := "user://just_cards.previous.json"
const TEMP_SAVE_PATH := "user://just_cards.tmp"
## Картинки лежат отдельными файлами, а в данных хранится только имя файла.
const IMAGES_DIR := "user://images/"
## Картинки уменьшаются до этого размера по большей стороне.
## Карточка на экране ~730 пикселей, так что запас есть.
const MAX_IMAGE_SIZE := 1024

## Версия формата файла. Пригодится, если мы когда-нибудь поменяем
## структуру данных: по номеру будет понятно, как читать старые файлы.
const FORMAT_VERSION := 1

## Все стаки. Каждый стак — это Dictionary (по смыслу как Struct в Blueprints):
## {
##     "id": "уникальная строка",
##     "name": "название стака",
##     "show_back": false,   # режим ROTATE ALL: true = карточки открываются стороной B
##     "loop": false,        # бесконечное повторение
##     "cards": [ карточка, карточка, ... ]
## }
## Карточка: { "front": сторона, "back": сторона }
## Сторона:  { "text": "слово", "image": "имя_файла.jpg" или "" }
var stacks: Array[Dictionary] = []

var _save_queued := false
## Уже загруженные картинки, чтобы не читать файл с диска каждый раз.
## Храним только несколько последних: каждая картинка занимает ~3 МБ
## видеопамяти, а на айфоне браузер перезапускает страницу, если памяти
## становится слишком много.
var _texture_cache := {}
const TEXTURE_CACHE_SIZE := 6


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(IMAGES_DIR)
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
		"loop": false,
		# По дизайну в новом стаке сразу есть одна пустая карточка.
		"cards": [new_card()],
	}


static func _make_id() -> String:
	# Время в миллисекундах + случайное число: двух одинаковых не будет.
	return "%d_%06d" % [Time.get_unix_time_from_system() * 1000.0, randi() % 1000000]


# ---------------------------------------------------------------------------
# Стаки
# ---------------------------------------------------------------------------

func create_stack(stack_name: String) -> Dictionary:
	var stack := new_stack(stack_name.strip_edges())
	stacks.append(stack)
	_stacks_changed()
	return stack


func delete_stack(stack_id: String) -> void:
	var index := _find_index(stack_id)
	if index == -1:
		return
	for card in stacks[index]["cards"]:
		_delete_card_images(card)
	stacks.remove_at(index)
	_stacks_changed()


func rename_stack(stack_id: String, new_name: String) -> void:
	var stack := find_stack(stack_id)
	if stack.is_empty():
		return
	stack["name"] = new_name.strip_edges()
	_stacks_changed()


## Возвращает стак по id или пустой Dictionary, если такого нет.
func find_stack(stack_id: String) -> Dictionary:
	var index := _find_index(stack_id)
	return stacks[index] if index != -1 else {}


func has_stacks() -> bool:
	return not stacks.is_empty()


## Режим ROTATE ALL: какой стороной открываются карточки стака.
func set_show_back(stack_id: String, value: bool) -> void:
	_set_stack_flag(stack_id, "show_back", value)


## Бесконечное повторение карточек.
func set_loop(stack_id: String, value: bool) -> void:
	_set_stack_flag(stack_id, "loop", value)


func _set_stack_flag(stack_id: String, key: String, value: bool) -> void:
	var stack := find_stack(stack_id)
	if stack.is_empty():
		return
	stack[key] = value
	queue_save()


func _find_index(stack_id: String) -> int:
	for i in stacks.size():
		if stacks[i].get("id") == stack_id:
			return i
	return -1


# ---------------------------------------------------------------------------
# Карточки. Карточку определяют стак и номер карточки в нём.
# side — это "front" (сторона A) или "back" (сторона B).
# ---------------------------------------------------------------------------

## Добавляет пустую карточку в конец стака и возвращает её номер.
func add_card(stack_id: String) -> int:
	var stack := find_stack(stack_id)
	if stack.is_empty():
		return -1
	stack["cards"].append(new_card())
	_cards_changed(stack_id)
	return stack["cards"].size() - 1


## Удаляет карточку. Если она была последней, вместо неё появляется
## пустая: в стаке всегда есть хотя бы одна карточка.
func delete_card(stack_id: String, card_index: int) -> void:
	var cards := _cards(stack_id)
	if card_index < 0 or card_index >= cards.size():
		return
	_delete_card_images(cards[card_index])
	cards.remove_at(card_index)
	if cards.is_empty():
		cards.append(new_card())
	_cards_changed(stack_id)


func card_count(stack_id: String) -> int:
	return _cards(stack_id).size()


## Возвращает сторону карточки: {"text": ..., "image": ...}.
func get_side(stack_id: String, card_index: int, side: String) -> Dictionary:
	var cards := _cards(stack_id)
	if card_index < 0 or card_index >= cards.size():
		return new_side()
	return cards[card_index][side]


func set_card_text(stack_id: String, card_index: int, side: String, text: String) -> void:
	var data := get_side(stack_id, card_index, side)
	if data["text"] == text:
		return
	data["text"] = text
	# Экраны тут оповещать не нужно: текст и так уже на экране. Только сохраняем.
	queue_save()


## Сохраняет картинку на сторону карточки. Большие фото уменьшаются.
func set_card_image(stack_id: String, card_index: int, side: String, image: Image) -> void:
	var data := get_side(stack_id, card_index, side)
	_delete_image_file(data["image"])
	data["image"] = _store_image(image)
	_cards_changed(stack_id)


func remove_card_image(stack_id: String, card_index: int, side: String) -> void:
	var data := get_side(stack_id, card_index, side)
	_delete_image_file(data["image"])
	data["image"] = ""
	_cards_changed(stack_id)


func _cards(stack_id: String) -> Array:
	return find_stack(stack_id).get("cards", [])


# ---------------------------------------------------------------------------
# Картинки
# ---------------------------------------------------------------------------

## Возвращает картинку по имени файла (или null, если файла нет).
func get_image_texture(file_name: String) -> Texture2D:
	if file_name == "":
		return null
	if _texture_cache.has(file_name):
		# Переставляем в конец: эта картинка снова «свежая».
		var cached: Texture2D = _texture_cache[file_name]
		_texture_cache.erase(file_name)
		_texture_cache[file_name] = cached
		return cached
	var image := Image.load_from_file(IMAGES_DIR + file_name)
	if image == null or image.is_empty():
		return null
	image.generate_mipmaps() # чтобы уменьшенная картинка не «рябила»
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[file_name] = texture
	# Dictionary в Godot помнит порядок добавления: первый ключ — самый старый.
	while _texture_cache.size() > TEXTURE_CACHE_SIZE:
		_texture_cache.erase(_texture_cache.keys()[0])
	return texture


## Выбросить все загруженные картинки из памяти (например, при выходе из стака).
func clear_texture_cache() -> void:
	_texture_cache.clear()


## Уменьшает картинку и сохраняет в файл. Возвращает имя файла.
func _store_image(image: Image) -> String:
	image = image.duplicate()
	var longest := maxi(image.get_width(), image.get_height())
	if longest > MAX_IMAGE_SIZE:
		var k := float(MAX_IMAGE_SIZE) / longest
		image.resize(roundi(image.get_width() * k), roundi(image.get_height() * k), Image.INTERPOLATE_LANCZOS)
	# Фото сохраняем в JPG (меньше места), картинки с прозрачностью — в PNG.
	var has_alpha := image.detect_alpha() != Image.ALPHA_NONE
	var file_name := _make_id() + (".png" if has_alpha else ".jpg")
	if has_alpha:
		image.save_png(IMAGES_DIR + file_name)
	else:
		image.convert(Image.FORMAT_RGB8)
		image.save_jpg(IMAGES_DIR + file_name, 0.85)
	return file_name


func _delete_card_images(card: Dictionary) -> void:
	_delete_image_file(card["front"]["image"])
	_delete_image_file(card["back"]["image"])


func _delete_image_file(file_name: String) -> void:
	if file_name == "":
		return
	_texture_cache.erase(file_name)
	DirAccess.remove_absolute(IMAGES_DIR + file_name)


## Удаляет файлы картинок, на которые больше не ссылается ни одна карточка
## (например, после загрузки резервной копии).
func _cleanup_unused_images() -> void:
	var used := {}
	for stack in stacks:
		for card in stack["cards"]:
			used[card["front"]["image"]] = true
			used[card["back"]["image"]] = true
	for file_name in DirAccess.get_files_at(IMAGES_DIR):
		if not used.has(file_name):
			_delete_image_file(file_name)


# ---------------------------------------------------------------------------
# Оповещения
# ---------------------------------------------------------------------------

func _stacks_changed() -> void:
	stacks_changed.emit()
	queue_save()


func _cards_changed(stack_id: String) -> void:
	cards_changed.emit(stack_id)
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
		stack["loop"] = bool(raw.get("loop", false))
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
		# Имя файла берём только «чистое», без папок: защита от странных файлов копии.
		side["image"] = str(raw.get("image", "")).get_file()
	return side


# ---------------------------------------------------------------------------
# Резервная копия (кнопка сохранить / загрузить)
# ---------------------------------------------------------------------------

## Весь архив одним текстом: стаки и сами картинки (в виде текста base64),
## чтобы копия была полной и её можно было перенести на другое устройство.
func export_backup_text() -> String:
	var data := _to_save_data()
	var images := {}
	for stack in stacks:
		for card in stack["cards"]:
			for side in ["front", "back"]:
				var file_name: String = card[side]["image"]
				if file_name != "" and FileAccess.file_exists(IMAGES_DIR + file_name):
					images[file_name] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(IMAGES_DIR + file_name))
	data["images"] = images
	return JSON.stringify(data)


## Загружает стаки из текста резервной копии. Возвращает false,
## если файл не похож на копию Just Cards.
func import_backup_text(text: String) -> bool:
	var loaded: Variant = _parse(text)
	if loaded == null:
		return false
	var data: Dictionary = JSON.parse_string(text)
	var images: Variant = data.get("images", {})
	if typeof(images) == TYPE_DICTIONARY:
		for file_name in images:
			var safe_name := str(file_name).get_file()
			var file := FileAccess.open(IMAGES_DIR + safe_name, FileAccess.WRITE)
			if file:
				file.store_buffer(Marshalls.base64_to_raw(str(images[file_name])))
			_texture_cache.erase(safe_name)
	stacks = loaded
	_cleanup_unused_images()
	_stacks_changed()
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
