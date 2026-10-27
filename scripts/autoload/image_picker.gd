extends Node
## ImagePicker — выбор картинки пользователем.
##
## Тот же приём, что в BackupIO: снаружи одна функция pick_image(),
## а внутри два разных механизма:
## - Windows и Android: системное окно выбора файла;
## - браузер айфона: системный выбор фото (галерея, камера, «Файлы»).
## Результат приходит сигналом image_picked.

signal image_picked(image: Image)

# В браузере картинку сразу уменьшаем и поворачиваем как надо
# (фото с айфона хранят поворот отдельно, и без этого они бывают «на боку»),
# а в Godot передаём уже готовый JPG в виде текста base64.
const WEB_PICKER_JS := """
window.justCardsPickImage = function (callback) {
	const input = document.createElement("input");
	input.type = "file";
	input.accept = "image/*";
	input.onchange = async () => {
		const file = input.files && input.files[0];
		if (!file) return;
		try {
			const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
			const k = Math.min(1, %d / Math.max(bitmap.width, bitmap.height));
			const canvas = document.createElement("canvas");
			canvas.width = Math.round(bitmap.width * k);
			canvas.height = Math.round(bitmap.height * k);
			canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
			callback(canvas.toDataURL("image/jpeg", 0.88).split(",")[1]);
		} catch (e) {
			console.error("Не удалось прочитать картинку", e);
		}
	};
	input.click();
};
"""

const FILE_FILTER := "*.png, *.jpg, *.jpeg, *.webp ; Картинки"

var _web_callback: JavaScriptObject
var _dialog: FileDialog


func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(WEB_PICKER_JS % AppData.MAX_IMAGE_SIZE, true)
		_web_callback = JavaScriptBridge.create_callback(_on_web_image)


func pick_image() -> void:
	if OS.has_feature("android"):
		# На Android для чтения чужих фото нужно разрешение. Система спросит
		# пользователя один раз, дальше будет помнить ответ.
		OS.request_permission("android.permission.READ_MEDIA_IMAGES")
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").justCardsPickImage(_web_callback)
		return
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.use_native_dialog = true
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = PackedStringArray([FILE_FILTER])
	_dialog.file_selected.connect(_on_file_selected)
	add_child(_dialog)
	_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	# На Android вместо пути приходит ссылка вида content://..., и у неё
	# нет расширения. Поэтому читаем «сырые» байты и сами определяем формат
	# по первым байтам файла. Так работает и на Windows, и на Android.
	var image := image_from_bytes(FileAccess.get_file_as_bytes(path))
	if image:
		image_picked.emit(image)


## Определяет формат картинки по «подписи» в начале файла и загружает её.
static func image_from_bytes(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50: # PNG
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8: # JPG
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = image.load_webp_from_buffer(bytes)
	return image if error == OK else null


func _on_web_image(args: Array) -> void:
	var image := Image.new()
	if image.load_jpg_from_buffer(Marshalls.base64_to_raw(str(args[0]))) == OK:
		image_picked.emit(image)
