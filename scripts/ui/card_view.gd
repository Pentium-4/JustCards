class_name CardView
extends Control
## Одна карточка на экране: слово, картинка, кнопки на карточке.
##
## Карточка ничего не знает о стаке и о сохранении. Она умеет:
##   - показать сторону: show_side({"text": ..., "image": ...});
##   - красиво перевернуться: flip_to(новая сторона);
##   - сообщить сигналом, что пользователь что-то сделал.
## Что с этим делать (сохранить текст, удалить карточку, листать),
## решает экран стака. Так карточку можно менять, не трогая остальное.

signal text_edited(text: String)
signal add_image_pressed
signal delete_pressed
signal flip_pressed
signal prev_pressed
signal next_pressed
## direction: +1 = к следующей карточке (свайп влево), -1 = к предыдущей.
signal swiped(direction: int)
## Картинку перетащили в корзину. Экран спросит «REMOVE?» и вызовет finish_image_drag.
signal image_remove_requested

const FLIP_SHADER := preload("res://shaders/card_flip.gdshader")
const FLIP_HALF_TIME := 0.22 # половина переворота, в секундах

## Минимальная длина свайпа в пикселях макета.
const SWIPE_DISTANCE := 110.0
const WORD_MAX_FONT := 100
const WORD_MIN_FONT := 46
## Где стоит поле слова без картинки и с картинкой (по макету).
const WORD_Y_NO_IMAGE := 656.0
const WORD_Y_WITH_IMAGE := 1060.0
const TRASH_MAGNET := 60.0

@onready var _add_image_button: IconButton = %AddImageButton
@onready var _trash_button: IconButton = %TrashButton
@onready var _image_frame: Control = %ImageFrame
@onready var _image: TextureRect = %Image
@onready var _word_edit: LineEdit = %WordEdit
@onready var _prev_button: IconButton = %PrevButton
@onready var _next_button: IconButton = %NextButton
@onready var _flip_button: IconButton = %FlipButton

var _flip_material: ShaderMaterial
var _flipping := false
var _image_gesture := LongPressGesture.new()
var _image_ghost: TextureRect
var _over_trash := false
var _swipe_start := Vector2.ZERO
var _swipe_tracking := false
var _navigation_set := false


func _ready() -> void:
	# Кнопки на карточке просто пересылают нажатия наружу.
	_add_image_button.pressed.connect(add_image_pressed.emit)
	_trash_button.pressed.connect(delete_pressed.emit)
	_flip_button.pressed.connect(flip_pressed.emit)
	_prev_button.pressed.connect(prev_pressed.emit)
	_next_button.pressed.connect(next_pressed.emit)
	_word_edit.text_changed.connect(_on_word_changed)
	_word_edit.resized.connect(_fit_word_font)

	# Для переворота: шейдер вешается на корень карточки, а все дочерние
	# узлы берут его через Use Parent Material. У картинки свой шейдер.
	_flip_material = ShaderMaterial.new()
	_flip_material.shader = FLIP_SHADER
	_use_parent_material_recursive(self)

	_image.gui_input.connect(_on_image_input)
	_image.resized.connect(_update_image_shader)
	_image_gesture.drag_started.connect(_on_image_drag_started)
	_image_gesture.drag_moved.connect(_on_image_drag_moved)
	_image_gesture.drag_ended.connect(_on_image_drag_ended)


func _use_parent_material_recursive(node: Node) -> void:
	for child in node.get_children(true): # true = вместе со «внутренними» узлами кнопок
		if child is CanvasItem and child != _image:
			child.use_parent_material = true
		_use_parent_material_recursive(child)


func _process(delta: float) -> void:
	_image_gesture.update(delta, get_global_mouse_position())


# ---------------------------------------------------------------------------
# Что показывать
# ---------------------------------------------------------------------------

func show_side(side: Dictionary) -> void:
	_word_edit.text = side.get("text", "")
	_fit_word_font()
	var texture := AppData.get_image_texture(side.get("image", ""))
	_image.texture = texture
	var has_image := texture != null
	_image_frame.visible = has_image
	_add_image_button.visible = not has_image
	_word_edit.position.y = WORD_Y_WITH_IMAGE if has_image else WORD_Y_NO_IMAGE
	_update_image_shader()


## Стрелки видны, только если карточек больше одной.
## Если повтор выключен, на первой карточке исчезает стрелка «назад»,
## а на последней — стрелка «вперёд».
func set_navigation(visible_arrows: bool, prev_enabled: bool, next_enabled: bool) -> void:
	_set_arrow_visible(_prev_button, visible_arrows and prev_enabled)
	_set_arrow_visible(_next_button, visible_arrows and next_enabled)
	_navigation_set = true


## Плавно показывает или прячет стрелку.
func _set_arrow_visible(arrow: IconButton, show: bool) -> void:
	# Первый раз (карточка только появилась) — без анимации.
	if not _navigation_set or arrow.visible == show:
		arrow.visible = show
		return
	if show:
		arrow.visible = true
		arrow.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(arrow, "modulate:a", 1.0 if show else 0.0, 0.2)
	if not show:
		tween.tween_callback(arrow.hide)


## Убрать курсор из поля слова (и спрятать клавиатуру на телефоне).
func release_word_focus() -> void:
	if _word_edit.has_focus():
		_word_edit.release_focus()


func _on_word_changed(text: String) -> void:
	_fit_word_font()
	text_edited.emit(text)


## Длинные слова уменьшаются, чтобы влезть в поле.
func _fit_word_font() -> void:
	var font := _word_edit.get_theme_font("font")
	var available := _word_edit.size.x - 70.0
	var width := font.get_string_size(_word_edit.text, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_MAX_FONT).x
	var font_size := WORD_MAX_FONT
	if width > available:
		font_size = maxi(WORD_MIN_FONT, floori(WORD_MAX_FONT * available / width))
	_word_edit.add_theme_font_size_override("font_size", font_size)


func _update_image_shader() -> void:
	var material := _image.material as ShaderMaterial
	material.set_shader_parameter("rect_size", _image.size)
	if _image.texture:
		material.set_shader_parameter("texture_size", _image.texture.get_size())


# ---------------------------------------------------------------------------
# Переворот
# ---------------------------------------------------------------------------

## Переворачивает карточку «как волчок» по часовой стрелке и на середине
## поворота подменяет содержимое на new_side. Можно дождаться через await.
func flip_to(new_side: Dictionary) -> void:
	if _flipping:
		return
	_flipping = true
	release_word_focus()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Центр карточки на экране: вокруг него и вращаем.
	var pivot := get_global_transform() * (size / 2.0)
	material = _flip_material
	for m in [_flip_material, _image.material]:
		m.set_shader_parameter("flip_pivot", pivot)

	var tween := create_tween()
	# Первая половина: от 0 до 90°, карточка становится «ребром».
	tween.tween_method(_set_flip_angle, 0.0, PI / 2.0, FLIP_HALF_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# В момент «ребром» подменяем сторону — этого не видно.
	tween.tween_callback(show_side.bind(new_side))
	# Вторая половина: новая сторона доворачивается от -90° до 0.
	tween.tween_method(_set_flip_angle, -PI / 2.0, 0.0, FLIP_HALF_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished

	material = null
	_set_flip_angle(0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_flipping = false


func _set_flip_angle(angle: float) -> void:
	_flip_material.set_shader_parameter("flip_angle", angle)
	(_image.material as ShaderMaterial).set_shader_parameter("flip_angle", angle)


# ---------------------------------------------------------------------------
# Свайп по карточке
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		release_word_focus() # нажали мимо поля — прячем клавиатуру
		_swipe_start = event.global_position
		_swipe_tracking = true
	elif _swipe_tracking:
		_swipe_tracking = false
		var delta: Vector2 = event.global_position - _swipe_start
		if absf(delta.x) > SWIPE_DISTANCE and absf(delta.x) > absf(delta.y) * 1.2:
			swiped.emit(1 if delta.x < 0 else -1)


# ---------------------------------------------------------------------------
# Перенос картинки в корзину
# ---------------------------------------------------------------------------

func _on_image_input(event: InputEvent) -> void:
	if _image_gesture.handle_input(event):
		_image.accept_event()


func _on_image_drag_started(pointer_position: Vector2) -> void:
	release_word_focus()
	_swipe_tracking = false
	_image_ghost = _image.duplicate() as TextureRect
	_image_ghost.material = _image.material.duplicate()
	_image_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_ghost.use_parent_material = false
	_image_ghost.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_image_ghost)
	_image_ghost.size = _image.size
	_image_ghost.global_position = _image.global_position
	# Призрак уменьшается вокруг точки, где лежит палец.
	_image_ghost.pivot_offset = pointer_position - _image.global_position
	_image.modulate.a = 0.25
	_over_trash = false
	create_tween().tween_property(_image_ghost, "scale", Vector2.ONE * 0.4, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_image_drag_moved(pointer_position: Vector2) -> void:
	if _image_ghost == null:
		return
	_image_ghost.global_position = pointer_position - _image_ghost.pivot_offset
	var over := _trash_button.get_global_rect().grow(TRASH_MAGNET).has_point(pointer_position)
	if over != _over_trash:
		_over_trash = over
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_trash_button, "scale", Vector2.ONE * (1.3 if over else 1.0), 0.2)
		tween.tween_property(_image_ghost, "scale", Vector2.ONE * (0.25 if over else 0.4), 0.2)


func _on_image_drag_ended(_pointer_position: Vector2) -> void:
	if _image_ghost == null:
		return
	create_tween().tween_property(_trash_button, "scale", Vector2.ONE, 0.2)
	if _over_trash:
		image_remove_requested.emit()
	else:
		finish_image_drag(false)


## Экран вызывает это после ответа на «REMOVE?».
func finish_image_drag(removed: bool) -> void:
	var ghost := _image_ghost
	_image_ghost = null
	if ghost == null:
		return
	var tween := create_tween().set_parallel()
	if removed:
		tween.tween_property(ghost, "scale", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		tween.tween_property(ghost, "global_position", _image.global_position, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ghost, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func():
		ghost.queue_free()
		_image.modulate.a = 1.0
	)
