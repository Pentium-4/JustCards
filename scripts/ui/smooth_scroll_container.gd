class_name SmoothScrollContainer
extends ScrollContainer
## ScrollContainer с плавной прокруткой колёсиком мыши.
##
## Обычный ScrollContainer прокручивает колёсиком рывками. Здесь мы
## перехватываем колёсико и плавно «доезжаем» до нужной позиции твином.
## Прокрутку пальцем на телефоне Godot и так делает плавной, с инерцией.

## На сколько пикселей макета прокручивает один щелчок колёсика.
@export var wheel_step := 260.0
## За сколько секунд доезжаем до цели.
@export var smooth_time := 0.25

var _target := 0.0
var _tween: Tween


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var direction := 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1.0
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1.0
	if direction == 0.0:
		return
	accept_event() # не даём стандартной прокрутке сработать
	var factor: float = event.factor if event.factor > 0.0 else 1.0
	scroll_smoothly(direction * wheel_step * factor)


## Плавно прокрутить на offset пикселей (плюс — вниз, минус — вверх).
func scroll_smoothly(offset: float) -> void:
	var bar := get_v_scroll_bar()
	var max_scroll := maxf(0.0, bar.max_value - bar.page)
	if not (_tween and _tween.is_running()):
		_target = scroll_vertical
	_target = clampf(_target + offset, 0.0, max_scroll)
	stop_smooth_scroll()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scroll_vertical", int(_target), smooth_time)


func stop_smooth_scroll() -> void:
	if _tween:
		_tween.kill()
