@tool
class_name IconButton
extends Button
## Универсальная кнопка приложения: фон (круг или скруглённый прямоугольник),
## белая иконка и/или текст, мягкая тень и анимация нажатия.
##
## Все настройки — в инспекторе (как Exposed-переменные у виджета в Unreal),
## поэтому одна и та же кнопка используется везде: корзина, галочка, START...
## Благодаря @tool в первой строке кнопка рисуется прямо в редакторе.
##
## Если включить Toggle Mode (в разделе BaseButton инспектора), кнопка станет
## переключателем: во включённом состоянии она чуть темнее и меньше.

## Цвет фона кнопки.
@export var bg_color := Color("#FB9D70"):
	set(value):
		bg_color = value
		queue_redraw()
## Радиус скругления. -1 = идеальный круг (или «таблетка» для широкой кнопки).
@export var corner_radius := -1:
	set(value):
		corner_radius = value
		queue_redraw()
## Мягкая тень под кнопкой.
@export var shadow := true:
	set(value):
		shadow = value
		queue_redraw()

@export_group("Icon")
## Иконка. Лучше белая: цвет задаётся через Icon Color.
@export var icon_texture: Texture2D:
	set(value):
		icon_texture = value
		_update_children()
@export var icon_color := Color.WHITE:
	set(value):
		icon_color = value
		_update_children()
## Размер иконки относительно кнопки (0.6 = 60% от меньшей стороны).
@export_range(0.1, 1.5) var icon_scale := 0.6:
	set(value):
		icon_scale = value
		_update_children()
## Поворот иконки. Так из крестика получается плюс (45°).
@export_range(-180, 180) var icon_rotation_degrees := 0.0:
	set(value):
		icon_rotation_degrees = value
		_update_children()

@export_group("Caption")
## Текст на кнопке (START, ROTATE ALL).
@export var caption := "":
	set(value):
		caption = value
		_update_children()
@export var caption_font_size := 64:
	set(value):
		caption_font_size = value
		_update_children()

## Насколько уменьшается нажатая кнопка.
const PRESSED_SCALE := 0.9
## Насколько темнеет нажатая кнопка (0 = никак, 1 = до чёрного).
const PRESSED_DARKEN := 0.12

var _icon_shadow: TextureRect
var _icon_rect: TextureRect
var _label: Label
var _press_amount := 0.0 # 0 = отпущена, 1 = нажата; анимируется твином
var _tween: Tween


func _init() -> void:
	flat = true # стандартный фон Button не рисуем, рисуем свой в _draw()
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Внутренние дочерние узлы: создаются кодом и не сохраняются в сцену,
	# поэтому в дереве сцены их не видно — снаружи кнопка выглядит одним узлом.
	_icon_shadow = _make_icon_rect()
	_icon_shadow.modulate = Color(0.2, 0.15, 0.05, 0.22)
	_icon_rect = _make_icon_rect()
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_icon_shadow, false, Node.INTERNAL_MODE_FRONT)
	add_child(_icon_rect, false, Node.INTERNAL_MODE_FRONT)
	add_child(_label, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	resized.connect(_update_children)
	button_down.connect(_animate_press)
	button_up.connect(_animate_press)
	toggled.connect(func(_on: bool): _animate_press())
	mouse_exited.connect(_animate_press)
	_update_children()
	_press_amount = 1.0 if _is_down() else 0.0
	_apply_press()


func _make_icon_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


func _update_children() -> void:
	if _icon_rect == null:
		return
	pivot_offset = size / 2.0
	var side := minf(size.x, size.y) * icon_scale
	var icon_size := Vector2(side, side)
	for rect in [_icon_shadow, _icon_rect]:
		rect.texture = icon_texture
		rect.visible = icon_texture != null
		rect.size = icon_size
		rect.pivot_offset = icon_size / 2.0
		rect.rotation_degrees = icon_rotation_degrees
		rect.position = (size - icon_size) / 2.0
	_icon_shadow.position += Vector2(1.5, 2.5)
	_icon_rect.self_modulate = icon_color
	_label.text = caption
	_label.visible = caption != ""
	_label.add_theme_font_size_override("font_size", caption_font_size)
	_label.position = Vector2.ZERO
	_label.size = size
	queue_redraw()


func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color.darkened(PRESSED_DARKEN * _press_amount)
	var radius := int(minf(size.x, size.y) / 2.0) if corner_radius < 0 else corner_radius
	style.set_corner_radius_all(radius)
	style.corner_detail = 20
	if shadow:
		style.shadow_color = Color(0.2, 0.12, 0.05, 0.3 * (1.0 - 0.5 * _press_amount))
		style.shadow_size = 16
		style.shadow_offset = Vector2(6, 8) * (1.0 - 0.5 * _press_amount)
	draw_style_box(style, Rect2(Vector2.ZERO, size))


## Обновить вид кнопки, если её состояние поменяли из кода
## (например, set_pressed_no_signal у переключателя).
func sync_state() -> void:
	_animate_press()


func _is_down() -> bool:
	var mode := get_draw_mode()
	return mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED


## Плавно переводит кнопку в нажатое или отпущенное состояние.
func _animate_press() -> void:
	var target := 1.0 if _is_down() else 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_press_amount, _press_amount, target, 0.18)


func _set_press_amount(value: float) -> void:
	_press_amount = value
	_apply_press()


func _apply_press() -> void:
	scale = Vector2.ONE * lerpf(1.0, PRESSED_SCALE, _press_amount)
	modulate.a = 0.5 if disabled else 1.0
	queue_redraw()


func _set(property: StringName, _value: Variant) -> bool:
	# Когда кнопку выключают (disabled), делаем её полупрозрачной.
	if property == &"disabled":
		_apply_press.call_deferred()
	return false
