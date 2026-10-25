class_name BlurOverlay
extends Control
## Размытый фон под попапами и под экраном карточек.
##
## Узел растягивается на весь экран, размывает всё, что нарисовано ПОД ним,
## и заодно не пропускает нажатия к экрану внизу.
## Внутри два прохода шейдера blur_pass.gdshader:
##   1) горизонтальное размытие;
##   2) BackBufferCopy «фотографирует» результат;
##   3) вертикальное размытие поверх этой фотографии.

const BLUR_SHADER := preload("res://shaders/blur_pass.gdshader")

## Сила размытия в пикселях макета.
@export var blur_radius := 48.0
## Цвет лёгкого затемнения фона (альфа = сила).
@export var tint := Color(0.12, 0.08, 0.05, 0.2)
## Длительность появления и исчезновения, в секундах.
@export var fade_time := 0.3

var _pass_h: ColorRect
var _pass_v: ColorRect
var _amount := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pass_h = _make_pass(Vector2(1, 0))
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	_pass_v = _make_pass(Vector2(0, 1))
	_set_amount(_amount)


func _make_pass(direction: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BLUR_SHADER
	material.set_shader_parameter("direction", direction)
	rect.material = material
	add_child(rect)
	return rect


## Плавно размыть фон. Возвращает твин, его можно дождаться через await.
func appear() -> Tween:
	return _fade_to(1.0)


## Плавно вернуть резкость.
func disappear() -> Tween:
	return _fade_to(0.0)


func _fade_to(target: float) -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_amount, _amount, target, fade_time)
	return tween


func _set_amount(value: float) -> void:
	_amount = value
	if _pass_h == null:
		return
	_pass_h.material.set_shader_parameter("radius", blur_radius * value)
	_pass_v.material.set_shader_parameter("radius", blur_radius * value)
	var t := tint
	t.a *= value
	_pass_v.material.set_shader_parameter("tint", t)
