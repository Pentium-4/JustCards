class_name LongPressGesture
extends RefCounted
## Распознаёт жест «нажал — подержал — потащил».
##
## Одна и та же логика нужна в двух местах: плитка стака на главном экране
## и картинка на карточке. Вместо того чтобы копировать код, он вынесен
## в отдельный объект (по смыслу как Actor Component в Unreal): узел создаёт
## LongPressGesture, передаёт ему события ввода и подписывается на сигналы.
##
## Распознаёт:
##   - короткое нажатие                → tapped
##   - долгое нажатие и перенос        → drag_started / drag_moved / drag_ended
##   - палец сдвинулся до срабатывания → ничего (это прокрутка или свайп,
##                                        событие уходит родителю)

signal tapped
signal drag_started(pointer_position: Vector2)
signal drag_moved(pointer_position: Vector2)
signal drag_ended(pointer_position: Vector2)

## Сколько секунд держать палец, чтобы «поднять» объект.
var long_press_time := 0.45
## Если палец сдвинулся дальше этого (в пикселях макета) до срабатывания,
## значит, пользователь прокручивает или свайпает.
var move_tolerance := 24.0

# Маленький «конечный автомат»: жест всегда в одном из трёх состояний.
enum State { NONE, PRESSING, DRAGGING }
var _state := State.NONE
var _press_position := Vector2.ZERO
var _press_time := 0.0


## Передай сюда событие из _gui_input. Возвращает true, если событие нужно
## «съесть» (accept_event), чтобы оно не ушло родителю.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_state = State.PRESSING
			_press_position = event.global_position
			_press_time = 0.0
			return false
		var was_dragging := _state == State.DRAGGING
		match _state:
			State.PRESSING:
				tapped.emit()
			State.DRAGGING:
				drag_ended.emit(event.global_position)
		_state = State.NONE
		return was_dragging

	if event is InputEventMouseMotion:
		if _state == State.PRESSING and event.global_position.distance_to(_press_position) > move_tolerance:
			_state = State.NONE # это прокрутка или свайп, а не нажатие
		elif _state == State.DRAGGING:
			drag_moved.emit(event.global_position)
			return true
	return false


## Вызывай каждый кадр из _process: здесь отсчитывается время удержания.
func update(delta: float, pointer_position: Vector2) -> void:
	if _state != State.PRESSING:
		return
	_press_time += delta
	if _press_time >= long_press_time:
		_state = State.DRAGGING
		drag_started.emit(pointer_position)


func is_dragging() -> bool:
	return _state == State.DRAGGING
