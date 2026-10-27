class_name BasePopup
extends Control
## Родительский класс для всех попапов (как родительский Widget Blueprint).
##
## Он умеет одно: красиво появиться (фон размывается, панель «выпрыгивает»)
## и красиво исчезнуть. Конкретные попапы (создание стака, подтверждение
## удаления) наследуются от него через «extends BasePopup» и добавляют
## только свои кнопки. Так анимация описана в одном месте.
##
## В сцене попапа должны быть два узла: Blur (BlurOverlay) и Panel.

## Отправляется, когда попап закрылся и удаляется.
signal closed

## Группа, в которую записываются все открытые попапы. Группы в Godot —
## это как теги у акторов в Unreal: по ним удобно найти все нужные узлы.
const GROUP := &"popups"

@onready var _blur: BlurOverlay = $Blur
@onready var _panel: Control = $Panel

var _closing := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group(GROUP)
	open()


## Что делать при «Назад» / Esc. По умолчанию просто закрыться;
## попапы-наследники могут поменять поведение (см. confirm_popup.gd).
func cancel() -> void:
	close()


func is_closing() -> bool:
	return _closing


func open() -> void:
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2.ONE * 0.85
	_panel.modulate.a = 0.0
	_blur.appear()
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)


func close() -> void:
	if _closing:
		return
	_closing = true
	_blur.disappear()
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "scale", Vector2.ONE * 0.85, 0.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.2)
	await get_tree().create_timer(_blur.fade_time).timeout
	closed.emit()
	queue_free()
